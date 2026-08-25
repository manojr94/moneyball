require 'csv'

# Bulk-imports employees (and optional initial salaries) from a CSV.
#
# Dry-run and commit share one code path: both wrap the row loop in a
# transaction and roll back on any error. Dry-run additionally rolls back on
# success. This is the "preview matches commit" guarantee — the same
# validations, uniqueness checks, and callback side-effects run in both modes.
#
# The row loop runs to completion even after the first error so HR gets a full
# error list on a single upload rather than one error per re-upload. Errors are
# capped at MAX_ERRORS entries in the response; row processing continues past
# the cap so the summary counts remain accurate.
class ImportEmployees
  MAX_ROWS = 10_000
  MAX_ERRORS = 100

  REQUIRED_HEADERS = %w[
    employee_number first_name last_name email country_code
    department_name job_title job_level hire_date
  ].freeze

  Result = Struct.new(
    :committed, :dry_run, :rows_total, :rows_valid, :rows_invalid,
    :employees_created, :salaries_created, :errors, :header_error,
    keyword_init: true
  ) do
    def success?
      header_error.nil? && rows_invalid.zero?
    end
  end

  RowError = Struct.new(:row, :employee_number, :messages, keyword_init: true)

  def self.call(csv_source, dry_run:, actor: nil)
    new(csv_source, dry_run: dry_run, actor: actor).call
  end

  def initialize(csv_source, dry_run:, actor: nil)
    @csv_source = csv_source
    @dry_run    = dry_run
    @actor      = actor
    @state      = ImportState.new
  end

  def call
    table, header_error = Parser.parse(@csv_source)
    return header_failure_result(header_error) if header_error

    ActiveRecord::Base.transaction do
      table.each_with_index { |row, idx| process_row(idx + 2, row) } # header is line 1
      raise ActiveRecord::Rollback if @dry_run || @state.errors.any?
    end
    build_result
  end

  private

  def process_row(row_num, row)
    RowImporter.new(row_num: row_num, row: row, state: @state, actor: @actor).call
  end

  def header_failure_result(header_error)
    Result.new(
      committed: false, dry_run: @dry_run,
      rows_total: 0, rows_valid: 0, rows_invalid: 0,
      employees_created: 0, salaries_created: 0,
      errors: [], header_error: header_error
    )
  end

  def build_result
    committed = !@dry_run && @state.errors.empty?
    Result.new(
      committed: committed, dry_run: @dry_run,
      rows_total: @state.rows_total,
      rows_valid: @state.rows_valid,
      rows_invalid: @state.rows_total - @state.rows_valid,
      employees_created: committed ? @state.employees_created : 0,
      salaries_created: committed ? @state.salaries_created : 0,
      errors: @state.errors, header_error: nil
    )
  end

  # Header validation, BOM stripping, and CSV parsing. Returns [table, err] where
  # err is a human-readable string when the file is unusable as a whole.
  class Parser
    def self.parse(source)
      text = source.is_a?(String) ? source : source.read
      text = strip_bom(text.to_s)
      table = CSV.parse(text, headers: true, skip_blanks: true)
      err = validate_headers(table.headers) || validate_size(table)
      [err ? [] : table, err]
    rescue CSV::MalformedCSVError => e
      [[], "malformed CSV: #{e.message}"]
    end

    def self.strip_bom(text)
      text.sub(/\A\xEF\xBB\xBF/, '').sub(/\A\uFEFF/, '')
    end

    def self.validate_headers(headers)
      return 'file is empty or has no header row' if headers.nil? || headers.compact.empty?

      missing = REQUIRED_HEADERS - headers.compact.map { |h| h.to_s.strip }
      "missing required column(s): #{missing.join(', ')}" if missing.any?
    end

    def self.validate_size(table)
      "file has #{table.size} rows; max is #{MAX_ROWS}" if table.size > MAX_ROWS
    end
  end

  # Accumulates counts, seen-so-far maps, and error list across rows. One per
  # import call; shared between the outer service and each RowImporter.
  class ImportState
    attr_reader :errors, :seen_numbers, :seen_emails, :dept_cache
    attr_accessor :rows_total, :rows_valid, :employees_created, :salaries_created

    def initialize
      @errors = []
      @seen_numbers = {}
      @seen_emails  = {}
      @dept_cache   = {}
      @rows_total = @rows_valid = @employees_created = @salaries_created = 0
    end

    def record_error(row_num, employee_number, messages)
      return if @errors.size >= MAX_ERRORS

      @errors << RowError.new(row: row_num, employee_number: employee_number, messages: Array(messages))
    end
  end

  # Processes a single CSV row: extracts attributes, checks in-file duplicates,
  # saves the employee, then optionally creates a salary via RecordSalaryChange.
  class RowImporter
    SALARY_FIELDS = %w[salary_amount salary_currency salary_effective_date].freeze

    def initialize(row_num:, row:, state:, actor:)
      @row_num = row_num
      @row     = row
      @state   = state
      @actor   = actor
    end

    def call
      @state.rows_total += 1
      @attrs = RowAttrs.extract(@row)
      return if duplicate_in_file?

      employee = build_employee
      if employee.save && maybe_create_salary(employee)
        @state.employees_created += 1
        @state.rows_valid += 1
      elsif employee.errors.any?
        @state.record_error(@row_num, @attrs[:employee_number], employee.errors.full_messages)
      end
    end

    private

    def duplicate_in_file?
      dup = duplicate_seen
      return false unless dup

      field, prior = dup
      error("duplicate #{field} in this file (also on row #{prior})")
      true
    end

    def duplicate_seen
      if @attrs[:employee_number] && (prior = @state.seen_numbers[@attrs[:employee_number]])
        ['employee_number', prior]
      elsif @attrs[:email] && (prior = @state.seen_emails[@attrs[:email].downcase])
        ['email', prior]
      else
        remember_row
        nil
      end
    end

    def remember_row
      @state.seen_numbers[@attrs[:employee_number]] = @row_num if @attrs[:employee_number]
      @state.seen_emails[@attrs[:email].downcase] = @row_num if @attrs[:email]
    end

    def build_employee
      Employee.new(
        @attrs.slice(:employee_number, :first_name, :last_name, :email, :country_code,
                     :job_title, :job_level, :hire_date, :status, :terminated_on)
              .merge(department: resolve_department(@attrs[:department_name]))
      )
    end

    def resolve_department(name)
      return nil if name.blank?

      key = name.downcase
      @state.dept_cache[key] ||= Department.where('LOWER(name) = ?', key).first
    end

    def maybe_create_salary(employee)
      return true if SALARY_FIELDS.none? { |f| @attrs[f.to_sym] }

      missing = missing_salary_fields
      return error("salary: missing #{missing.join(', ')}") && false if missing.any?

      RecordSalaryChange.call(**salary_args(employee))
      @state.salaries_created += 1
      true
    rescue RecordSalaryChange::Error, ArgumentError, Money::Currency::UnknownCurrency => e
      error("salary: #{e.message}")
      false
    end

    def missing_salary_fields
      [
        ('salary_amount' if @attrs[:salary_amount].blank?),
        ('salary_currency' if @attrs[:salary_currency].blank?)
      ].compact
    end

    def salary_args(employee)
      {
        employee: employee,
        amount_minor_units: to_minor_units(@attrs[:salary_amount], @attrs[:salary_currency]),
        currency: @attrs[:salary_currency],
        effective_date: @attrs[:salary_effective_date] || @attrs[:hire_date],
        reason: 'new_hire',
        created_by_id: @actor&.id
      }
    end

    def to_minor_units(amount_str, currency)
      cleaned = amount_str.to_s.delete(',').strip
      Money.from_amount(BigDecimal(cleaned), currency).fractional
    end

    def error(message)
      @state.record_error(@row_num, @attrs[:employee_number], [message])
    end
  end

  # Extracts, trims, and normalizes a CSV::Row into a symbol-keyed hash.
  # Also handles the "no salary fields present" path by leaving them nil.
  module RowAttrs
    STRING_FIELDS = %w[
      employee_number first_name last_name email
      department_name job_title job_level hire_date terminated_on
      salary_amount salary_effective_date
    ].freeze
    UPCASE_FIELDS = %w[country_code salary_currency].freeze

    module_function

    def extract(row)
      attrs = {}
      STRING_FIELDS.each { |f| attrs[f.to_sym] = trim(row[f]) }
      UPCASE_FIELDS.each { |f| attrs[f.to_sym] = trim(row[f])&.upcase }
      attrs[:status] = trim(row['status']) || 'active'
      attrs
    end

    def trim(value)
      return nil if value.nil?

      trimmed = value.to_s.strip
      trimmed.empty? ? nil : trimmed
    end
  end
end
