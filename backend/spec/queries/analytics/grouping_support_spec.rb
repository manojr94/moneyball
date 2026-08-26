require 'rails_helper'

RSpec.describe Analytics::GroupingSupport do
  describe 'module constants' do
    it 'GROUPS maps the four expected keys to SQL column expressions' do
      expect(Analytics::GroupingSupport::GROUPS.keys).to match_array(%w[region country department level])
    end

    it 'FILTERS maps the four expected param keys to SQL column expressions' do
      expect(Analytics::GroupingSupport::FILTERS.keys).to match_array(%i[region country_code department_id job_level])
    end
  end

  describe 'group keys' do
    before do
      pay_zone = create(:pay_zone)
      create(:country, code: 'US', region: 'na', pay_zone: pay_zone)
      dept     = create(:department)
      employee = create(:employee, country_code: 'US', department: dept,
                                   job_level: 'L3', status: 'active')
      create(:salary, employee: employee, currency: 'USD')
    end

    %w[region country department level].each do |group|
      it "PayAnalytics and CompaRatioAnalytics return identical group keys for group_by=#{group}" do
        pay_keys   = PayAnalytics.new(group_by: group).call[:groups].pluck(:key)
        compa_keys = CompaRatioAnalytics.new(group_by: group).call[:groups].pluck(:key)
        expect(pay_keys).to eq(compa_keys)
      end
    end
  end
end
