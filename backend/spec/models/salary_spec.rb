require 'rails_helper'

RSpec.describe Salary, type: :model do
  describe 'validations' do
    subject(:salary) { build(:salary) }

    it { is_expected.to be_valid }

    it 'belongs to an employee' do
      salary = create(:salary)
      expect(salary.employee).to be_a(Employee)
    end

    context 'amount_minor_units' do
      it 'rejects zero' do
        salary.amount_minor_units = 0
        expect(salary).not_to be_valid
        expect(salary.errors[:amount_minor_units]).to be_present
      end

      it 'rejects negative amounts' do
        salary.amount_minor_units = -1
        expect(salary).not_to be_valid
      end

      it 'rejects nil' do
        salary.amount_minor_units = nil
        expect(salary).not_to be_valid
      end
    end

    context 'currency' do
      it 'rejects a blank currency' do
        salary.currency = ''
        expect(salary).not_to be_valid
      end

      it 'rejects a non-ISO currency code' do
        salary.currency = 'XYZ'
        expect(salary).not_to be_valid
        expect(salary.errors[:currency]).to be_present
      end

      it 'rejects a lowercase code' do
        salary.currency = 'usd'
        expect(salary).not_to be_valid
      end

      it 'accepts JPY (zero-decimal currency)' do
        salary.currency = 'JPY'
        salary.amount_minor_units = 8_000_000
        expect(salary).to be_valid
      end

      it 'accepts KWD (three-decimal currency)' do
        salary.currency = 'KWD'
        salary.amount_minor_units = 1_200_000
        expect(salary).to be_valid
      end
    end

    context 'reason' do
      it 'rejects an unrecognised reason' do
        salary.reason = 'bonus'
        expect(salary).not_to be_valid
        expect(salary.errors[:reason]).to be_present
      end

      it 'rejects a blank reason' do
        salary.reason = ''
        expect(salary).not_to be_valid
      end

      Salary::VALID_REASONS.each do |r|
        it "accepts reason '#{r}'" do
          salary.reason = r
          expect(salary).to be_valid
        end
      end
    end

    it 'rejects a missing effective_date' do
      salary.effective_date = nil
      expect(salary).not_to be_valid
    end
  end

  describe 'immutability' do
    let!(:salary) { create(:salary) }

    it 'cannot be updated' do
      result = salary.update(amount_minor_units: salary.amount_minor_units + 1)
      expect(result).to be false
      expect(salary.errors[:base]).to include(match(/immutable/))
    end

    it 'raises on update!' do
      expect { salary.update!(amount_minor_units: salary.amount_minor_units + 1) }
        .to raise_error(ActiveRecord::RecordNotSaved)
    end

    it 'cannot be destroyed' do
      result = salary.destroy
      expect(result).to be false
      expect(Salary.exists?(salary.id)).to be true
    end

    it 'raises on destroy!' do
      expect { salary.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
    end
  end

  describe '.as_of scope' do
    let(:employee) { create(:employee) }

    let!(:jan) { create(:salary, employee: employee, effective_date: Date.new(2024, 1, 1), amount_minor_units: 8_000_00) }
    let!(:jul) { create(:salary, employee: employee, effective_date: Date.new(2024, 7, 1), amount_minor_units: 9_000_00) }

    it 'returns the most recent salary on or before the date' do
      expect(employee.salaries.as_of(Date.new(2024, 6, 30)).first).to eq(jan)
    end

    it 'returns the salary on its exact effective_date' do
      expect(employee.salaries.as_of(Date.new(2024, 7, 1)).first).to eq(jul)
    end

    it 'returns nil when no salary exists before the date' do
      expect(employee.salaries.as_of(Date.new(2023, 12, 31)).first).to be_nil
    end
  end

  describe 'same-day supersede' do
    let(:employee) { create(:employee) }

    it 'prefers the later-inserted row when two salaries share an effective_date' do
      first  = create(:salary, employee: employee, effective_date: Date.new(2024, 3, 1), amount_minor_units: 5_000_00)
      second = create(:salary, employee: employee, effective_date: Date.new(2024, 3, 1), amount_minor_units: 5_500_00)

      result = employee.salaries.as_of(Date.new(2024, 3, 1)).first
      expect(result).to eq(second)
      expect(result).not_to eq(first)
    end
  end

  describe 'backdated insert' do
    let(:employee) { create(:employee) }

    it 'does not affect point-in-time queries before the backdated date' do
      current = create(:salary, employee: employee, effective_date: Date.new(2024, 6, 1), amount_minor_units: 9_000_00)

      # Now backdate a salary before the existing one
      create(:salary, employee: employee, effective_date: Date.new(2024, 1, 1), amount_minor_units: 8_000_00)

      expect(employee.salaries.as_of(Date.new(2024, 5, 31)).first.amount_minor_units).to eq(8_000_00)
      expect(employee.salaries.as_of(Date.new(2024, 6, 1)).first).to eq(current)
    end
  end
end

RSpec.describe Employee, type: :model do
  describe '#salary_on and #current_salary' do
    let(:employee) { create(:employee) }

    it 'returns nil when the employee has no salaries' do
      expect(employee.salary_on(Date.current)).to be_nil
      expect(employee.current_salary).to be_nil
    end

    context 'with a salary history' do
      let!(:jan) { create(:salary, employee: employee, effective_date: Date.new(2024, 1, 1), amount_minor_units: 8_000_00) }
      let!(:jul) { create(:salary, employee: employee, effective_date: Date.new(2024, 7, 1), amount_minor_units: 9_500_00) }

      it 'returns nil before the first salary date' do
        expect(employee.salary_on(Date.new(2023, 12, 31))).to be_nil
      end

      it 'returns the correct salary at each point in time' do
        expect(employee.salary_on(Date.new(2024, 1, 1))).to eq(jan)
        expect(employee.salary_on(Date.new(2024, 6, 30))).to eq(jan)
        expect(employee.salary_on(Date.new(2024, 7, 1))).to eq(jul)
        expect(employee.salary_on(Date.new(2025, 1, 1))).to eq(jul)
      end

      it '#current_salary delegates to salary_on(Date.current)' do
        travel_to(Date.new(2024, 3, 15)) do
          expect(employee.current_salary).to eq(jan)
        end

        travel_to(Date.new(2024, 9, 1)) do
          expect(employee.current_salary).to eq(jul)
        end
      end
    end
  end
end
