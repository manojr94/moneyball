require 'rails_helper'

RSpec.describe Analytics::GroupingSupport do
  describe 'shared constants' do
    it 'defines identical GROUPS in both analytics services' do
      expect(PayAnalytics::GROUPS).to eq(CompaRatioAnalytics::GROUPS)
    end

    it 'defines identical LABEL_SOURCE in both analytics services' do
      expect(PayAnalytics::LABEL_SOURCE).to eq(CompaRatioAnalytics::LABEL_SOURCE)
    end

    it 'defines identical FILTERS in both analytics services' do
      expect(PayAnalytics::FILTERS).to eq(CompaRatioAnalytics::FILTERS)
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
