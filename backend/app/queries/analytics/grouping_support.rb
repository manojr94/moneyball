module Analytics
  # Shared grouping/filtering infrastructure for PayAnalytics and CompaRatioAnalytics.
  # Both services aggregate salary data by the same four group_by keys (region, country,
  # department, level) with the same filter params, label resolution, and date-parsing
  # helpers. This module extracts that common logic so it lives in one place.
  module GroupingSupport
    GROUPS = {
      'region' => 'countries.region',
      'country' => 'employees.country_code',
      'department' => 'employees.department_id',
      'level' => 'employees.job_level'
    }.freeze

    LABEL_SOURCE = { 'country' => :country, 'department' => :department, 'region' => :region }.freeze
    REGION_LABELS = { 'na' => 'NA', 'latam' => 'LATAM', 'emea' => 'EMEA', 'apac' => 'APAC' }.freeze

    FILTERS = {
      region: 'countries.region',
      country_code: 'employees.country_code',
      department_id: 'employees.department_id',
      job_level: 'employees.job_level'
    }.freeze

    UNCONVERTIBLE_SQL = <<~SQL.squish.freeze
      WITH current_salary AS (
        SELECT DISTINCT ON (employee_id) currency FROM salaries
        WHERE effective_date <= %<as_of>s
        ORDER BY employee_id, effective_date DESC, id DESC
      )
      SELECT DISTINCT cs.currency FROM current_salary cs
      WHERE cs.currency <> 'USD'
        AND NOT EXISTS (
          SELECT 1 FROM exchange_rates er
          WHERE er.currency = cs.currency AND er.effective_date <= %<rate_date>s
        )
      ORDER BY cs.currency
    SQL

    def group_col
      GROUPS.fetch(@group_by)
    end

    def validate(params)
      return "group_by must be one of: #{GROUPS.keys.join(', ')}" unless GROUPS.key?(@group_by)
      return 'as_of is not a valid date'     if params[:as_of].present?     && @as_of.nil?
      return 'rate_date is not a valid date' if params[:rate_date].present? && @rate_date.nil?

      validate_filters(params)
    end

    def validate_filters(params)
      return unless params[:region].present? && Country::REGIONS.exclude?(params[:region])

      "region must be one of: #{Country::REGIONS.join(', ')}"
    end

    def extract_filters(params)
      FILTERS.filter_map { |key, col| [col, params[key]] if params[key].present? }.to_h
    end

    def unconvertible_currencies
      connection.select_values(format(UNCONVERTIBLE_SQL, as_of: q(@as_of), rate_date: q(@rate_date)))
    end

    def excluded_clause(excluded)
      return '' if excluded.empty?

      "AND cs.currency NOT IN (#{excluded.map { |c| q(c) }.join(',')})"
    end

    def filter_clauses
      return '' if @filters.empty?

      @filters.map { |col, val| "AND #{col} = #{q(val)}" }.join(' ')
    end

    def label_lookup
      @label_lookup ||=
        case LABEL_SOURCE[@group_by]
        when :country    then Country.pluck(:code, :name).to_h
        when :department then Department.pluck(:id, :name).to_h { |id, n| [id.to_s, n] }
        when :region     then REGION_LABELS
        else                  {}
        end
    end

    def parse_date(value, default)
      return default if value.blank?

      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    delegate :connection, to: :'ActiveRecord::Base'

    def q(value)
      connection.quote(value)
    end
  end
end
