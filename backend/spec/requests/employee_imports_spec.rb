require 'rails_helper'

RSpec.describe 'Employee imports API', type: :request do
  let(:admin)          { create(:user, :hr_admin) }
  let(:viewer)         { create(:user, :viewer) }
  let(:admin_headers)  { { 'Authorization' => "Bearer #{AuthToken.encode(admin)}" } }
  let(:viewer_headers) { { 'Authorization' => "Bearer #{AuthToken.encode(viewer)}" } }

  before do
    create(:department, name: 'Engineering', slug: 'engineering')
    create(:country, code: 'US')
  end

  def csv_body(rows = [valid_row])
    headers = %w[employee_number first_name last_name email country_code
                 department_name job_title job_level hire_date]
    ([headers.join(',')] + rows.map { |r| headers.map { |h| r[h] }.join(',') }).join("\n")
  end

  def valid_row
    { 'employee_number' => 'IMP001', 'first_name' => 'Alice', 'last_name' => 'Smith',
      'email' => 'alice@example.com', 'country_code' => 'US',
      'department_name' => 'Engineering', 'job_title' => 'Engineer',
      'job_level' => 'L3', 'hire_date' => '2024-01-01' }
  end

  # ---------------------------------------------------------------------------
  # Auth
  # ---------------------------------------------------------------------------
  it 'returns 401 without a token' do
    post '/imports/employees', params: { csv: csv_body }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns 403 for a viewer' do
    post '/imports/employees', params: { csv: csv_body }, headers: viewer_headers
    expect(response).to have_http_status(:forbidden)
  end

  # ---------------------------------------------------------------------------
  # Missing / malformed input
  # ---------------------------------------------------------------------------
  it 'returns 422 when neither :file nor :csv is provided' do
    post '/imports/employees', headers: admin_headers
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body['error']).to include('file is required')
  end

  it 'returns 422 when the CSV is missing required columns' do
    post '/imports/employees', params: { csv: 'employee_number\nEMP001' }, headers: admin_headers
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body['header_error']).to include('missing required column')
  end

  # ---------------------------------------------------------------------------
  # Dry-run (default)
  # ---------------------------------------------------------------------------
  describe 'dry-run mode (default)' do
    it 'returns 200 and does not persist anything' do
      expect do
        post '/imports/employees', params: { csv: csv_body }, headers: admin_headers
      end.not_to change(Employee, :count)
      expect(response).to have_http_status(:ok)
    end

    it 'reports the preview shape with summary and empty errors' do
      post '/imports/employees', params: { csv: csv_body }, headers: admin_headers
      body = response.parsed_body
      expect(body['dry_run']).to be(true)
      expect(body['committed']).to be(false)
      expect(body['summary']).to include('rows_total' => 1, 'rows_valid' => 1, 'rows_invalid' => 0)
      expect(body['errors']).to eq([])
    end

    it 'still returns 200 (not 422) when the dry-run reveals row errors' do
      body = csv_body([valid_row.merge('email' => 'not-an-email')])
      post '/imports/employees', params: { csv: body }, headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['errors'].size).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # Commit mode
  # ---------------------------------------------------------------------------
  describe 'commit mode' do
    it 'returns 201 and persists all rows on success' do
      expect do
        post '/imports/employees', params: { csv: csv_body, dry_run: 'false' }, headers: admin_headers
      end.to change(Employee, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(response.parsed_body['committed']).to be(true)
    end

    it 'returns 422 and persists nothing when any row fails' do
      body = csv_body([
                        valid_row.merge('employee_number' => 'OK1', 'email' => 'ok1@x.com'),
                        valid_row.merge('employee_number' => 'BAD', 'email' => 'bad@x.com', 'first_name' => '')
                      ])
      expect do
        post '/imports/employees', params: { csv: body, dry_run: 'false' }, headers: admin_headers
      end.not_to change(Employee, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['committed']).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # Multipart upload
  # ---------------------------------------------------------------------------
  it 'accepts a multipart file upload under :file' do
    file = Tempfile.new(['import', '.csv']).tap do |f|
      f.write(csv_body)
      f.rewind
    end
    upload = Rack::Test::UploadedFile.new(file.path, 'text/csv')
    expect do
      post '/imports/employees', params: { file: upload, dry_run: 'false' }, headers: admin_headers
    end.to change(Employee, :count).by(1)
    expect(response).to have_http_status(:created)
  ensure
    file&.close
    file&.unlink
  end
end
