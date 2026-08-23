require 'rails_helper'

RSpec.describe Employee, type: :model do
  describe 'validations' do
    it 'is valid with required attributes' do
      employee = build(:employee)
      expect(employee).to be_valid
    end

    it 'requires an employee_number' do
      employee = build(:employee, employee_number: nil)
      expect(employee).not_to be_valid
      expect(employee.errors[:employee_number]).to include("can't be blank")
    end

    it 'requires a unique employee_number' do
      create(:employee, employee_number: 'EMP00001')
      duplicate = build(:employee, employee_number: 'EMP00001')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:employee_number]).to include('has already been taken')
    end

    it 'requires a first_name' do
      employee = build(:employee, first_name: nil)
      expect(employee).not_to be_valid
      expect(employee.errors[:first_name]).to include("can't be blank")
    end

    it 'requires a last_name' do
      employee = build(:employee, last_name: nil)
      expect(employee).not_to be_valid
      expect(employee.errors[:last_name]).to include("can't be blank")
    end

    it 'requires an email' do
      employee = build(:employee, email: nil)
      expect(employee).not_to be_valid
      expect(employee.errors[:email]).to include("can't be blank")
    end

    it 'requires a valid email format' do
      employee = build(:employee, email: 'not-an-email')
      expect(employee).not_to be_valid
      expect(employee.errors[:email]).to be_present
    end

    it 'requires a unique email' do
      create(:employee, email: 'jane@example.com')
      duplicate = build(:employee, email: 'jane@example.com')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to include('has already been taken')
    end

    it 'requires a country_code' do
      employee = build(:employee, country_code: nil)
      expect(employee).not_to be_valid
      expect(employee.errors[:country_code]).to include("can't be blank")
    end

    it 'requires a hire_date' do
      employee = build(:employee, hire_date: nil)
      expect(employee).not_to be_valid
      expect(employee.errors[:hire_date]).to include("can't be blank")
    end

    it 'requires a job_title' do
      employee = build(:employee, job_title: nil)
      expect(employee).not_to be_valid
      expect(employee.errors[:job_title]).to include("can't be blank")
    end

    it 'requires a job_level' do
      employee = build(:employee, job_level: nil)
      expect(employee).not_to be_valid
      expect(employee.errors[:job_level]).to include("can't be blank")
    end

    it 'rejects an invalid status value' do
      employee = build(:employee, status: 'invalid')
      expect(employee).not_to be_valid
      expect(employee.errors[:status]).to be_present
    end
  end

  describe 'terminated_on validation' do
    it 'is invalid when terminated_on is set but status is not terminated' do
      employee = build(:employee, status: 'active', terminated_on: Date.current)
      expect(employee).not_to be_valid
      expect(employee.errors[:terminated_on]).to include('can only be set when status is terminated')
    end

    it 'is valid when terminated_on is set and status is terminated' do
      country = create(:country)
      employee = build(:employee, status: 'terminated', terminated_on: Date.current,
                       country_code: country.code)
      expect(employee).to be_valid
    end

    it 'is valid when terminated_on is nil and status is active' do
      employee = build(:employee, status: 'active', terminated_on: nil)
      expect(employee).to be_valid
    end
  end

  describe 'soft-delete' do
    it 'deactivate! sets status to inactive' do
      employee = create(:employee)
      employee.deactivate!
      expect(employee.reload.status).to eq('inactive')
    end

    it 'terminate! sets status to terminated and records the date' do
      employee = create(:employee)
      date = Date.new(2024, 6, 1)
      employee.terminate!(on_date: date)
      employee.reload
      expect(employee.status).to eq('terminated')
      expect(employee.terminated_on).to eq(date)
    end

    it 'terminate! uses today as default date' do
      employee = create(:employee)
      employee.terminate!
      expect(employee.reload.terminated_on).to eq(Date.current)
    end
  end

  describe '.active scope' do
    it 'returns only active employees' do
      active = create(:employee, status: 'active')
      inactive = create(:employee, status: 'inactive')
      terminated = create(:employee, status: 'terminated', terminated_on: Date.current)

      result = Employee.active
      expect(result).to include(active)
      expect(result).not_to include(inactive)
      expect(result).not_to include(terminated)
    end
  end

  describe 'unconfigured country auto-creation' do
    it 'saves an employee in an unconfigured country and creates the country with needs_review' do
      na_zone = create(:pay_zone, name: 'North America', slug: 'default-na')
      department = create(:department)

      expect(Country.exists?(code: 'US')).to be false

      employee = Employee.new(
        employee_number: 'EMP99999',
        first_name: 'John',
        last_name: 'Smith',
        email: 'john.smith@example.com',
        country_code: 'US',
        department: department,
        job_title: 'Analyst',
        job_level: 'L2',
        hire_date: Date.new(2023, 1, 15)
      )

      expect(employee.save).to be true
      expect(Country.exists?(code: 'US')).to be true
      expect(Country.find('US').needs_review).to be true
    end

    it 'saves successfully when country_code is not in COUNTRY_DATA but country already exists' do
      existing_country = create(:country, code: 'XK')
      department = create(:department)

      employee = Employee.new(
        employee_number: 'EMP88888',
        first_name: 'Alice',
        last_name: 'Smith',
        email: 'alice.smith@example.com',
        country_code: 'XK',
        department: department,
        job_title: 'Manager',
        job_level: 'L5',
        hire_date: Date.new(2022, 3, 1)
      )

      expect(employee.save).to be true
    end
  end
end
