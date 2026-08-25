require 'rails_helper'

RSpec.describe 'GET /analytics/band_coverage', type: :request do
  let(:admin)          { create(:user, :hr_admin) }
  let(:viewer)         { create(:user, :viewer) }
  let(:admin_headers)  { { 'Authorization' => "Bearer #{AuthToken.encode(admin)}" } }
  let(:viewer_headers) { { 'Authorization' => "Bearer #{AuthToken.encode(viewer)}" } }

  let(:zone)   { create(:pay_zone, name: 'North America', slug: 'na-bc') }
  let(:dept)   { create(:department) }
  let(:us)     { create(:country, code: 'US', name: 'United States', default_currency: 'USD', region: 'na', pay_zone: zone) }
  let(:unzoned_country) { create(:country, code: 'XZ', name: 'Unzoned', default_currency: 'USD', region: 'na', pay_zone: nil) }

  def employ(country:, title: 'Engineer', level: 'L3', status: 'active', number: nil)
    n = number || "BC#{SecureRandom.hex(3).upcase}"
    create(:employee, employee_number: n, country_code: country.code,
           department: dept, job_title: title, job_level: level,
           hire_date: 1.year.ago.to_date, status:,
           email: "#{n.downcase}@example.com")
  end

  it 'returns 401 without a token' do
    get '/analytics/band_coverage'
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns 200 for a viewer' do
    get '/analytics/band_coverage', headers: viewer_headers
    expect(response).to have_http_status(:ok)
  end

  it 'returns 200 for an hr_admin' do
    get '/analytics/band_coverage', headers: admin_headers
    expect(response).to have_http_status(:ok)
  end

  it 'returns the expected top-level shape' do
    get '/analytics/band_coverage', headers: viewer_headers
    body = response.parsed_body
    expect(body).to have_key('uncovered')
    expect(body).to have_key('unzoned')
  end

  # ---------------------------------------------------------------------------
  # Coverage report lists every uncovered title/level/zone (Key test)
  # ---------------------------------------------------------------------------
  describe 'uncovered combinations' do
    before do
      us  # ensure country row exists
      # Band covers Engineer L3 only
      create(:salary_band, pay_zone: zone, job_title: 'Engineer', job_level: 'L3',
             min_minor_units: 80_000_00, mid_minor_units: 100_000_00,
             max_minor_units: 130_000_00, effective_from: 2.years.ago.to_date)

      employ(country: us, title: 'Engineer', level: 'L3')  # covered
      employ(country: us, title: 'Manager',  level: 'L5')  # uncovered
      employ(country: us, title: 'Analyst',  level: 'L2')  # uncovered
    end

    it 'lists exactly the uncovered (zone, title, level) combinations' do
      get '/analytics/band_coverage', headers: viewer_headers
      uncovered = response.parsed_body['uncovered']
      combo_keys = uncovered.map { |r| [r['pay_zone_id'], r['job_title'], r['job_level']] }
      expect(combo_keys).to contain_exactly(
        [zone.id, 'Manager', 'L5'],
        [zone.id, 'Analyst', 'L2']
      )
    end

    it 'includes pay_zone_name and employee_count in each row' do
      get '/analytics/band_coverage', headers: viewer_headers
      row = response.parsed_body['uncovered'].first
      expect(row.keys).to include('pay_zone_id', 'pay_zone_name', 'job_title', 'job_level', 'employee_count')
      expect(row['pay_zone_name']).to eq('North America')
      expect(row['employee_count']).to eq(1)
    end

    it 'does not list covered combinations' do
      get '/analytics/band_coverage', headers: viewer_headers
      uncovered = response.parsed_body['uncovered']
      covered_in_list = uncovered.any? { |r| r['job_title'] == 'Engineer' && r['job_level'] == 'L3' }
      expect(covered_in_list).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # Unzoned employees surface under :unzoned
  # ---------------------------------------------------------------------------
  describe 'unzoned employees' do
    before do
      unzoned_country  # ensure country row exists
      employ(country: unzoned_country, title: 'Engineer', level: 'L3')
    end

    it 'lists unzoned employees by country_code/title/level' do
      get '/analytics/band_coverage', headers: viewer_headers
      unzoned = response.parsed_body['unzoned']
      expect(unzoned).not_to be_empty
      row = unzoned.find { |r| r['country_code'] == 'XZ' }
      expect(row).not_to be_nil
      expect(row['job_title']).to eq('Engineer')
      expect(row['employee_count']).to eq(1)
    end

    it 'does not appear in the uncovered list' do
      get '/analytics/band_coverage', headers: viewer_headers
      uncovered = response.parsed_body['uncovered']
      xz_in_uncovered = uncovered.any? { |r| r.key?('country_code') }
      expect(xz_in_uncovered).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # Inactive / terminated employees are excluded
  # ---------------------------------------------------------------------------
  describe 'population filter' do
    before { us }

    it 'excludes inactive employees from uncovered list' do
      employ(country: us, title: 'Designer', level: 'L4', status: 'inactive')
      get '/analytics/band_coverage', headers: viewer_headers
      uncovered = response.parsed_body['uncovered']
      expect(uncovered.any? { |r| r['job_title'] == 'Designer' }).to be false
    end

    it 'excludes terminated employees from uncovered list' do
      e = employ(country: us, title: 'Designer', level: 'L4')
      e.terminate!(on_date: 1.month.ago.to_date)
      get '/analytics/band_coverage', headers: viewer_headers
      uncovered = response.parsed_body['uncovered']
      expect(uncovered.any? { |r| r['job_title'] == 'Designer' }).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # No uncovered combinations returns empty arrays
  # ---------------------------------------------------------------------------
  it 'returns empty arrays when all active employees have bands' do
    us
    create(:salary_band, pay_zone: zone, job_title: 'Engineer', job_level: 'L3',
           min_minor_units: 80_000_00, mid_minor_units: 100_000_00, max_minor_units: 130_000_00,
           effective_from: 2.years.ago.to_date)
    employ(country: us)
    get '/analytics/band_coverage', headers: viewer_headers
    body = response.parsed_body
    expect(body['uncovered']).to be_empty
    expect(body['unzoned']).to be_empty
  end
end
