require 'rails_helper'

RSpec.describe ImportEmployees do
  let(:department) { Department.find_by(slug: 'engineering') }

  before do
    create(:department, name: 'Engineering', slug: 'engineering')
    create(:country, code: 'US')
  end

  def csv(rows, headers: default_headers)
    ([headers.join(',')] + rows.map { |r| headers.map { |h| r[h] }.join(',') }).join("\n")
  end

  def default_headers
    %w[employee_number first_name last_name email country_code
       department_name job_title job_level hire_date]
  end

  def row(overrides = {})
    {
      'employee_number' => 'EMP001', 'first_name' => 'Alice', 'last_name' => 'Smith',
      'email' => 'alice@example.com', 'country_code' => 'US',
      'department_name' => 'Engineering', 'job_title' => 'Engineer', 'job_level' => 'L3',
      'hire_date' => '2024-01-01'
    }.merge(overrides)
  end

  # ---------------------------------------------------------------------------
  # Header validation
  # ---------------------------------------------------------------------------
  describe 'header validation' do
    it 'reports missing required columns as a header_error' do
      bad = "employee_number,first_name\nEMP001,Alice"
      result = described_class.call(bad, dry_run: true)
      expect(result.header_error).to include('missing required column')
      expect(result.header_error).to include('last_name')
    end

    it 'flags an empty file' do
      result = described_class.call('', dry_run: true)
      expect(result.header_error).to include('empty')
    end

    it 'accepts a header-only file with zero data rows' do
      result = described_class.call(csv([]), dry_run: false)
      expect(result.header_error).to be_nil
      expect(result.rows_total).to eq(0)
      expect(result.committed).to be(true)
    end

    it 'ignores extra columns not in the schema' do
      headers = default_headers + %w[notes cost_center]
      body    = csv([row.merge('notes' => 'hi', 'cost_center' => 'X')], headers: headers)
      expect { described_class.call(body, dry_run: false) }.to change(Employee, :count).by(1)
    end

    it 'is column-order agnostic' do
      shuffled = default_headers.reverse
      expect do
        described_class.call(csv([row], headers: shuffled), dry_run: false)
      end.to change(Employee, :count).by(1)
    end

    it 'strips a UTF-8 BOM from the first header' do
      body = "﻿#{csv([row])}"
      expect { described_class.call(body, dry_run: false) }.to change(Employee, :count).by(1)
    end

    it 'handles CRLF line endings' do
      body = csv([row]).gsub("\n", "\r\n")
      expect { described_class.call(body, dry_run: false) }.to change(Employee, :count).by(1)
    end

    it 'rejects a file over MAX_ROWS' do
      stub_const("#{described_class}::MAX_ROWS", 2)
      body = csv([row(no1), row(no2), row(no3)])
      result = described_class.call(body, dry_run: true)
      expect(result.header_error).to include('max is 2')
    end

    def no1 = { 'employee_number' => 'A1', 'email' => 'a1@x.com' }
    def no2 = { 'employee_number' => 'A2', 'email' => 'a2@x.com' }
    def no3 = { 'employee_number' => 'A3', 'email' => 'a3@x.com' }
  end

  # ---------------------------------------------------------------------------
  # Happy path — commit and dry-run
  # ---------------------------------------------------------------------------
  describe 'commit' do
    it 'persists all valid rows and returns a committed result' do
      body = csv([
                   row('employee_number' => 'EMP001', 'email' => 'a@x.com'),
                   row('employee_number' => 'EMP002', 'email' => 'b@x.com', 'first_name' => 'Bob')
                 ])
      expect { described_class.call(body, dry_run: false) }.to change(Employee, :count).by(2)
      result = described_class.call(csv([]), dry_run: false)
      expect(result.committed).to be(true)
    end

    it 'reports employees_created only when committed' do
      body = csv([row])
      result = described_class.call(body, dry_run: false)
      expect(result.employees_created).to eq(1)
      expect(result.committed).to be(true)
    end
  end

  describe 'dry-run' do
    it 'validates rows without persisting anything' do
      body = csv([row])
      expect { described_class.call(body, dry_run: true) }.not_to change(Employee, :count)
    end

    it 'reports rows_valid but employees_created stays zero' do
      body = csv([row])
      result = described_class.call(body, dry_run: true)
      expect(result.rows_valid).to eq(1)
      expect(result.employees_created).to eq(0)
    end

    it 'returns the same errors that a commit would (preview/commit parity)' do
      bad = csv([row('email' => 'not-an-email')])
      preview = described_class.call(bad, dry_run: true)
      committed = described_class.call(bad, dry_run: false)
      expect(preview.errors.map(&:messages)).to eq(committed.errors.map(&:messages))
    end
  end

  # ---------------------------------------------------------------------------
  # Atomicity — partial failure = full rollback
  # ---------------------------------------------------------------------------
  describe 'atomicity' do
    it 'rolls back everything when any row fails on commit' do
      body = csv([
                   row('employee_number' => 'GOOD1', 'email' => 'good1@x.com'),
                   row('employee_number' => 'GOOD2', 'email' => 'good2@x.com', 'first_name' => 'Bob'),
                   row('employee_number' => 'BAD',  'email' => 'bad@x.com', 'first_name' => '') # blank name
                 ])
      expect { described_class.call(body, dry_run: false) }.not_to change(Employee, :count)
    end

    it 'reports every failing row before rolling back, not just the first' do
      body = csv([
                   row('employee_number' => 'BAD1', 'email' => 'e1@x.com', 'first_name' => ''),
                   row('employee_number' => 'BAD2', 'email' => 'e2@x.com', 'last_name' => '')
                 ])
      result = described_class.call(body, dry_run: false)
      expect(result.errors.map(&:row)).to eq([2, 3])
    end

    it 'marks committed=false when any row fails' do
      body = csv([row('email' => 'nope')])
      result = described_class.call(body, dry_run: false)
      expect(result.committed).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # Duplicate detection
  # ---------------------------------------------------------------------------
  describe 'duplicate detection' do
    it 'flags a second row with the same employee_number as an in-file duplicate' do
      body = csv([
                   row('employee_number' => 'DUP', 'email' => 'a@x.com'),
                   row('employee_number' => 'DUP', 'email' => 'b@x.com')
                 ])
      result = described_class.call(body, dry_run: true)
      expect(result.errors.first.messages.first).to include('duplicate employee_number')
    end

    it 'flags a second row with the same email as an in-file duplicate' do
      body = csv([
                   row('employee_number' => 'A1', 'email' => 'same@x.com'),
                   row('employee_number' => 'A2', 'email' => 'same@x.com')
                 ])
      result = described_class.call(body, dry_run: true)
      expect(result.errors.first.messages.first).to include('duplicate email')
    end

    it 'rejects a row whose employee_number already exists in the database' do
      create(:employee, employee_number: 'EXISTS', department: department, country_code: 'US')
      body = csv([row('employee_number' => 'EXISTS', 'email' => 'new@x.com')])
      result = described_class.call(body, dry_run: true)
      expect(result.errors.first.messages.join).to include('has already been taken')
    end

    it 'fails an entire second import of the same file (duplicate detection across runs)' do
      body = csv([row('employee_number' => 'ONCE', 'email' => 'once@x.com')])
      described_class.call(body, dry_run: false)
      result = described_class.call(body, dry_run: false)
      expect(result.committed).to be(false)
      expect(result.rows_invalid).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # Salaries
  # ---------------------------------------------------------------------------
  describe 'optional salary column' do
    let(:salary_headers) do
      default_headers + %w[salary_amount salary_currency salary_effective_date]
    end

    it 'creates only the employee when no salary_* fields are provided' do
      body = csv([row], headers: salary_headers) # salary fields blank
      result = described_class.call(body, dry_run: false)
      expect(result.salaries_created).to eq(0)
      expect(result.employees_created).to eq(1)
    end

    it 'creates a salary in USD minor units (100x major)' do
      body = csv([row.merge('salary_amount' => '80000', 'salary_currency' => 'USD',
                            'salary_effective_date' => '2024-01-15')], headers: salary_headers)
      expect { described_class.call(body, dry_run: false) }.to change(Salary, :count).by(1)
      expect(Salary.last.amount_minor_units).to eq(8_000_000)
    end

    it 'creates a JPY salary with 1x minor units (exponent 0)' do
      body = csv([row.merge('salary_amount' => '80000', 'salary_currency' => 'JPY')],
                 headers: salary_headers)
      described_class.call(body, dry_run: false)
      expect(Salary.last.amount_minor_units).to eq(80_000)
      expect(Salary.last.currency).to eq('JPY')
    end

    it 'creates a KWD salary with 1000x minor units (exponent 3)' do
      body = csv([row.merge('salary_amount' => '80.500', 'salary_currency' => 'KWD')],
                 headers: salary_headers)
      described_class.call(body, dry_run: false)
      expect(Salary.last.amount_minor_units).to eq(80_500)
    end

    it 'defaults salary_effective_date to hire_date when omitted' do
      body = csv([row.merge('salary_amount' => '80000', 'salary_currency' => 'USD',
                            'hire_date' => '2023-06-15')], headers: salary_headers)
      described_class.call(body, dry_run: false)
      expect(Salary.last.effective_date).to eq(Date.new(2023, 6, 15))
    end

    it 'rejects a row with salary_amount but no salary_currency' do
      body = csv([row.merge('salary_amount' => '80000')], headers: salary_headers)
      result = described_class.call(body, dry_run: true)
      expect(result.errors.first.messages.first).to include('salary_currency')
    end

    it 'rejects a salary with an unknown currency' do
      body = csv([row.merge('salary_amount' => '80000', 'salary_currency' => 'XYZ')],
                 headers: salary_headers)
      result = described_class.call(body, dry_run: true)
      expect(result.errors.first.messages.join).to include('salary:')
    end

    it 'strips thousands-separator commas from salary_amount' do
      # CSV field with commas must be quoted, so build the line by hand.
      headers = salary_headers.join(',')
      data = row.merge('salary_amount' => '"80,000.00"', 'salary_currency' => 'USD')
      line = salary_headers.map { |h| data[h] }.join(',')
      described_class.call("#{headers}\n#{line}", dry_run: false)
      expect(Salary.last.amount_minor_units).to eq(8_000_000)
    end

    it 'records the actor as created_by on the salary' do
      admin = create(:user, :hr_admin)
      body = csv([row.merge('salary_amount' => '80000', 'salary_currency' => 'USD')],
                 headers: salary_headers)
      described_class.call(body, dry_run: false, actor: admin)
      expect(Salary.last.created_by_id).to eq(admin.id)
    end
  end

  # ---------------------------------------------------------------------------
  # Country auto-create (M1 invariant)
  # ---------------------------------------------------------------------------
  describe 'unconfigured country' do
    it 'auto-creates a novel country row flagged needs_review' do
      body = csv([row('country_code' => 'ZZ')])
      expect { described_class.call(body, dry_run: false) }.to change(Country, :count).by(1)
      expect(Country.find('ZZ').needs_review).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # Departments — not auto-created
  # ---------------------------------------------------------------------------
  describe 'unknown department' do
    it 'rejects a row whose department_name does not exist' do
      body = csv([row('department_name' => 'Nonexistent')])
      result = described_class.call(body, dry_run: true)
      expect(result.errors.first.messages.join).to include('Department')
    end

    it 'matches department name case-insensitively' do
      body = csv([row('department_name' => 'engineering')])
      expect { described_class.call(body, dry_run: false) }.to change(Employee, :count).by(1)
    end
  end

  # ---------------------------------------------------------------------------
  # Error cap
  # ---------------------------------------------------------------------------
  describe 'error cap' do
    it 'stops recording after MAX_ERRORS but continues to count rows_invalid' do
      stub_const("#{described_class}::MAX_ERRORS", 2)
      rows = 5.times.map { |i| row('employee_number' => "BAD#{i}", 'email' => "b#{i}@x.com", 'first_name' => '') }
      result = described_class.call(csv(rows), dry_run: true)
      expect(result.errors.size).to eq(2)
      expect(result.rows_invalid).to eq(5)
    end
  end
end
