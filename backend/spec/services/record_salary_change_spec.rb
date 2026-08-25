require 'rails_helper'

RSpec.describe RecordSalaryChange do
  let(:employee) { create(:employee) }

  def call(overrides = {})
    described_class.call(
      employee: employee,
      amount_minor_units: 100_000_00,
      currency: 'USD',
      effective_date: Date.new(2024, 1, 1),
      reason: 'new_hire',
      **overrides
    )
  end

  describe 'success path' do
    it 'persists a new salary row' do
      expect { call }.to change(Salary, :count).by(1)
    end

    it 'returns the created salary' do
      result = call
      expect(result).to be_a(Salary)
      expect(result).to be_persisted
    end

    it 'stores the correct attributes' do
      result = call(amount_minor_units: 8_500_00, currency: 'EUR',
                    effective_date: Date.new(2024, 6, 1), reason: 'merit')
      expect(result.amount_minor_units).to eq(8_500_00)
      expect(result.currency).to eq('EUR')
      expect(result.effective_date).to eq(Date.new(2024, 6, 1))
      expect(result.reason).to eq('merit')
    end

    it 'associates the salary with the given employee' do
      result = call
      expect(result.employee).to eq(employee)
    end

    it 'records the created_by_id' do
      user = create(:user)
      result = call(created_by_id: user.id)
      expect(result.created_by_id).to eq(user.id)
    end

    it 'accepts created_by_id: nil' do
      expect { call(created_by_id: nil) }.not_to raise_error
    end
  end

  describe 'point-in-time correctness via the service' do
    it 'builds an accurate salary history across multiple calls' do
      call(amount_minor_units: 8_000_00, effective_date: Date.new(2024, 1, 1), reason: 'new_hire')
      call(amount_minor_units: 9_000_00, effective_date: Date.new(2024, 7, 1), reason: 'merit')

      expect(employee.salary_on(Date.new(2024, 6, 30)).amount_minor_units).to eq(8_000_00)
      expect(employee.salary_on(Date.new(2024, 7, 1)).amount_minor_units).to eq(9_000_00)
    end

    it 'supports backdated salary entry' do
      call(amount_minor_units: 9_000_00, effective_date: Date.new(2024, 7, 1), reason: 'merit')
      call(amount_minor_units: 8_000_00, effective_date: Date.new(2024, 1, 1), reason: 'new_hire')

      expect(employee.salary_on(Date.new(2024, 5, 1)).amount_minor_units).to eq(8_000_00)
    end

    it 'same-day correction: second call supersedes the first' do
      call(amount_minor_units: 5_000_00, effective_date: Date.new(2024, 3, 1), reason: 'new_hire')
      call(amount_minor_units: 5_500_00, effective_date: Date.new(2024, 3, 1), reason: 'correction')

      expect(employee.salary_on(Date.new(2024, 3, 1)).amount_minor_units).to eq(5_500_00)
    end
  end

  describe 'validation failures' do
    it 'raises Error when the amount is zero' do
      expect { call(amount_minor_units: 0) }
        .to raise_error(RecordSalaryChange::Error, 'Amount minor units must be greater than 0')
    end

    it 'raises Error when the amount is negative' do
      expect { call(amount_minor_units: -1) }
        .to raise_error(RecordSalaryChange::Error, 'Amount minor units must be greater than 0')
    end

    it 'raises Error for an unknown currency' do
      expect { call(currency: 'XYZ') }
        .to raise_error(RecordSalaryChange::Error, 'Currency XYZ is not a recognised ISO 4217 currency code')
    end

    it 'raises Error when effective_date is missing' do
      expect { call(effective_date: nil) }
        .to raise_error(RecordSalaryChange::Error, "Effective date can't be blank")
    end

    it 'raises Error when reason is invalid' do
      expect { call(reason: 'bonus') }
        .to raise_error(RecordSalaryChange::Error, 'Reason is not included in the list')
    end

    it 'does not persist a salary row on validation failure' do
      expect { call(amount_minor_units: 0) }.to raise_error(RecordSalaryChange::Error)
      expect(Salary.count).to eq(0)
    end
  end
end
