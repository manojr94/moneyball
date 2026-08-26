require 'rails_helper'

RSpec.describe 'Employees API', type: :request do
  let(:admin)          { create(:user, :hr_admin) }
  let(:viewer)         { create(:user, :viewer) }
  let(:admin_headers)  { { 'Authorization' => "Bearer #{AuthToken.encode(admin)}" } }
  let(:viewer_headers) { { 'Authorization' => "Bearer #{AuthToken.encode(viewer)}" } }

  # ---------------------------------------------------------------------------
  # GET /employees
  # ---------------------------------------------------------------------------
  describe 'GET /employees' do
    let!(:dept_eng) { create(:department, name: 'Engineering', slug: 'engineering') }
    let!(:dept_hr)  { create(:department, name: 'HR', slug: 'hr') }

    before do
      create(:country, code: 'US')
      create(:country, code: 'DE')
      create(:employee, first_name: 'Alice', last_name: 'Adams',
                        department: dept_eng, country_code: 'US', status: 'active')
      create(:employee, first_name: 'Bob', last_name: 'Baker',
                        department: dept_hr, country_code: 'DE', status: 'inactive')
      create(:employee, first_name: 'Carol', last_name: 'Clark',
                        department: dept_eng, country_code: 'US', status: 'terminated',
                        terminated_on: 1.year.ago.to_date)
    end

    it 'returns 401 without a token' do
      get '/employees'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 200 with data and meta for an authenticated user' do
      get '/employees', headers: viewer_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to have_key('data')
      expect(body).to have_key('meta')
      expect(body['meta']).to include('per_page', 'next_cursor')
    end

    it 'includes expected fields in each employee object' do
      get '/employees', headers: viewer_headers
      emp = response.parsed_body['data'].first
      expect(emp.keys).to include(
        'id', 'employee_number', 'first_name', 'last_name', 'email',
        'country_code', 'department', 'job_title', 'job_level',
        'hire_date', 'status', 'terminated_on'
      )
      expect(emp['department'].keys).to include('id', 'name')
    end

    describe 'filtering by status' do
      it 'returns only active employees when status=active' do
        get '/employees', params: { status: 'active' }, headers: viewer_headers
        statuses = response.parsed_body['data'].pluck('status').uniq
        expect(statuses).to eq(['active'])
      end

      it 'returns only terminated employees when status=terminated' do
        get '/employees', params: { status: 'terminated' }, headers: viewer_headers
        statuses = response.parsed_body['data'].pluck('status').uniq
        expect(statuses).to eq(['terminated'])
      end

      it 'returns 422 for an invalid status value' do
        get '/employees', params: { status: 'bogus' }, headers: viewer_headers
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['error']).to include('status must be one of')
      end
    end

    describe 'filtering by department' do
      it 'returns only employees in the specified department' do
        get '/employees', params: { department_id: dept_eng.id }, headers: viewer_headers
        ids = response.parsed_body['data'].map { |e| e['department']['id'] }.uniq
        expect(ids).to eq([dept_eng.id])
      end

      it 'returns empty results for a department with no employees' do
        empty_dept = create(:department, name: 'Empty', slug: 'empty')
        get '/employees', params: { department_id: empty_dept.id }, headers: viewer_headers
        expect(response.parsed_body['data']).to be_empty
        expect(response.parsed_body['meta']['next_cursor']).to be_nil
      end
    end

    describe 'filtering by country' do
      it 'returns only employees in the specified country' do
        get '/employees', params: { country_code: 'US' }, headers: viewer_headers
        codes = response.parsed_body['data'].pluck('country_code').uniq
        expect(codes).to eq(['US'])
      end
    end

    describe 'filter combinations' do
      before do
        create(:employee, first_name: 'Dave', last_name: 'Dean',
                          department: dept_eng, country_code: 'US', status: 'active',
                          job_title: 'Software Engineer', job_level: 'L4')
      end

      it 'combines status and department filters (AND semantics)' do
        get '/employees', params: { status: 'active', department_id: dept_hr.id },
                          headers: viewer_headers
        expect(response.parsed_body['data']).to be_empty
      end

      it 'returns the matching employee when filters narrow to one' do
        get '/employees', params: { status: 'inactive', country_code: 'DE' },
                          headers: viewer_headers
        data = response.parsed_body['data']
        expect(data.size).to eq(1)
        expect(data.first['first_name']).to eq('Bob')
      end

      it 'filters by job_title alone' do
        get '/employees', params: { job_title: 'Software Engineer' }, headers: viewer_headers
        titles = response.parsed_body['data'].pluck('job_title').uniq
        expect(titles).to eq(['Software Engineer'])
      end

      it 'filters by job_level alone' do
        get '/employees', params: { job_level: 'L4' }, headers: viewer_headers
        levels = response.parsed_body['data'].pluck('job_level').uniq
        expect(levels).to eq(['L4'])
      end

      it 'combines status + department + country (three-way AND)' do
        get '/employees', params: { status: 'active', department_id: dept_eng.id,
                                    country_code: 'US' }, headers: viewer_headers
        data = response.parsed_body['data']
        expect(data.pluck('status').uniq).to eq(['active'])
        expect(data.map { |e| e['department']['id'] }.uniq).to eq([dept_eng.id])
        expect(data.pluck('country_code').uniq).to eq(['US'])
      end

      it 'combines all five filters and returns matching employees' do
        get '/employees', params: { status: 'active', department_id: dept_eng.id,
                                    country_code: 'US', job_title: 'Software Engineer',
                                    job_level: 'L4' }, headers: viewer_headers
        data = response.parsed_body['data']
        expect(data).not_to be_empty
        data.each do |e|
          expect(e['status']).to eq('active')
          expect(e['job_title']).to eq('Software Engineer')
          expect(e['job_level']).to eq('L4')
        end
      end

      it 'returns the full list when no filters are applied' do
        get '/employees', headers: viewer_headers
        expect(response.parsed_body['data'].size).to be > 1
      end
    end

    describe 'sorting' do
      before do
        # delete_all bypasses the before_destroy callback (which blocks destroy on Employee).
        # DatabaseCleaner uses the same bypass for test teardown.
        Employee.delete_all
        create(:employee, last_name: 'Zebra', department: dept_eng, country_code: 'US')
        create(:employee, last_name: 'Apple', department: dept_eng, country_code: 'US')
        create(:employee, last_name: 'Mango', department: dept_eng, country_code: 'US')
      end

      it 'defaults to ascending employee_number order' do
        get '/employees', headers: viewer_headers
        numbers = response.parsed_body['data'].pluck('employee_number')
        expect(numbers).to eq(numbers.sort)
      end

      it 'sorts by last_name ascending when sort=last_name' do
        get '/employees', params: { sort: 'last_name' }, headers: viewer_headers
        names = response.parsed_body['data'].pluck('last_name')
        expect(names).to eq(names.sort)
      end

      it 'falls back to employee_number for an unknown sort key' do
        get '/employees', params: { sort: 'invalid_key' }, headers: viewer_headers
        expect(response).to have_http_status(:ok)
        numbers = response.parsed_body['data'].pluck('employee_number')
        expect(numbers).to eq(numbers.sort)
      end
    end

    describe 'keyset pagination' do
      before do
        Employee.delete_all
        10.times { create(:employee, department: dept_eng, country_code: 'US') }
      end

      it 'respects per_page and returns next_cursor when more records exist' do
        get '/employees', params: { per_page: 3 }, headers: viewer_headers
        body = response.parsed_body
        expect(body['data'].size).to eq(3)
        expect(body['meta']['next_cursor']).to be_present
      end

      it 'returns nil next_cursor on the last page' do
        get '/employees', params: { per_page: 100 }, headers: viewer_headers
        expect(response.parsed_body['meta']['next_cursor']).to be_nil
      end

      it 'fetches the next page using the cursor and returns no duplicates' do
        get '/employees', params: { per_page: 4 }, headers: viewer_headers
        first_body  = response.parsed_body
        first_ids   = first_body['data'].pluck('id')
        next_cursor = first_body['meta']['next_cursor']

        get '/employees', params: { per_page: 4, cursor: next_cursor }, headers: viewer_headers
        second_ids = response.parsed_body['data'].pluck('id')

        expect(first_ids & second_ids).to be_empty
      end

      it 'walking all pages yields every employee exactly once' do
        all_ids = []
        cursor  = nil
        loop do
          get '/employees', params: { per_page: 3, cursor: cursor }.compact, headers: viewer_headers
          body = response.parsed_body
          all_ids += body['data'].pluck('id')
          cursor = body['meta']['next_cursor']
          break unless cursor
        end
        expect(all_ids.uniq.size).to eq(10)
        expect(all_ids.size).to eq(10)
      end

      it 'clamps per_page to MAX of 100' do
        get '/employees', params: { per_page: 999 }, headers: viewer_headers
        expect(response.parsed_body['meta']['per_page']).to eq(100)
      end

      it 'ignores a malformed cursor and returns the first page' do
        get '/employees', params: { cursor: 'not-valid-base64!!!', per_page: 3 },
                          headers: viewer_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['data'].size).to eq(3)
      end

      it 'returns nil next_cursor when the last page is exactly per_page records' do
        get '/employees', params: { per_page: 5 }, headers: viewer_headers
        first_cursor = response.parsed_body['meta']['next_cursor']
        expect(first_cursor).to be_present

        get '/employees', params: { per_page: 5, cursor: first_cursor }, headers: viewer_headers
        expect(response.parsed_body['data'].size).to eq(5)
        expect(response.parsed_body['meta']['next_cursor']).to be_nil
      end
    end

    describe 'pagination combined with filters' do
      before do
        Employee.delete_all
        5.times { create(:employee, department: dept_eng, country_code: 'US', status: 'active') }
        3.times { create(:employee, department: dept_hr,  country_code: 'DE', status: 'inactive') }
      end

      it 'walks all pages of a filtered set without duplicates or gaps' do
        all_ids = []
        cursor  = nil
        loop do
          get '/employees', params: { status: 'active', per_page: 2, cursor: cursor }.compact,
                            headers: viewer_headers
          body = response.parsed_body
          all_ids += body['data'].pluck('id')
          cursor = body['meta']['next_cursor']
          break unless cursor
        end
        expect(all_ids.uniq.size).to eq(5)
        expect(all_ids.size).to eq(5)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # GET /employees/:id
  # ---------------------------------------------------------------------------
  describe 'GET /employees/:id' do
    let!(:employee) { create(:employee) }

    it 'returns 401 without a token' do
      get "/employees/#{employee.id}"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the employee for an authenticated viewer' do
      get "/employees/#{employee.id}", headers: viewer_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['id']).to eq(employee.id)
    end

    it 'returns the employee for an authenticated admin' do
      get "/employees/#{employee.id}", headers: admin_headers
      expect(response).to have_http_status(:ok)
    end

    it 'returns 404 for a non-existent id' do
      get '/employees/0', headers: viewer_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------------
  # POST /employees
  # ---------------------------------------------------------------------------
  describe 'POST /employees' do
    let(:dept) { create(:department) }
    let(:valid_params) do
      {
        employee: {
          employee_number: 'NEW001',
          first_name: 'Diana',
          last_name: 'Duke',
          email: 'diana@example.com',
          country_code: 'US',
          department_id: dept.id,
          job_title: 'Product Manager',
          job_level: 'L4',
          hire_date: '2024-03-01'
        }
      }
    end

    before { create(:country, code: 'US') }

    it 'returns 401 without a token' do
      post '/employees', params: valid_params
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for a viewer' do
      post '/employees', params: valid_params, headers: viewer_headers
      expect(response).to have_http_status(:forbidden)
    end

    it 'creates an employee and returns 201 for an hr_admin' do
      expect do
        post '/employees', params: valid_params, headers: admin_headers
      end.to change(Employee, :count).by(1)
      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['first_name']).to eq('Diana')
      expect(body['employee_number']).to eq('NEW001')
    end

    it 'auto-creates an unconfigured country and still saves the employee' do
      params = valid_params.deep_merge(employee: { country_code: 'ZZ' })
      expect do
        post '/employees', params: params, headers: admin_headers
      end.to change(Employee, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(Country.find('ZZ').needs_review).to be(true)
    end

    it 'returns 422 for missing required fields' do
      post '/employees', params: { employee: { first_name: 'Oops' } },
                         headers: admin_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['errors']).to be_present
    end

    it 'returns 422 for a duplicate employee_number' do
      create(:employee, employee_number: 'DUP001', department: dept)
      params = valid_params.deep_merge(employee: { employee_number: 'DUP001' })
      post '/employees', params: params, headers: admin_headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 422 for a duplicate email' do
      create(:employee, email: 'diana@example.com', department: dept)
      post '/employees', params: valid_params, headers: admin_headers
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # ---------------------------------------------------------------------------
  # PATCH /employees/:id
  # ---------------------------------------------------------------------------
  describe 'PATCH /employees/:id' do
    let!(:employee) { create(:employee, status: 'active') }

    it 'returns 401 without a token' do
      patch "/employees/#{employee.id}", params: { employee: { job_title: 'CTO' } }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for a viewer' do
      patch "/employees/#{employee.id}", params: { employee: { job_title: 'CTO' } },
                                         headers: viewer_headers
      expect(response).to have_http_status(:forbidden)
    end

    it 'updates the employee and returns 200 for an hr_admin' do
      patch "/employees/#{employee.id}", params: { employee: { job_title: 'Staff Engineer' } },
                                         headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['job_title']).to eq('Staff Engineer')
      expect(employee.reload.job_title).to eq('Staff Engineer')
    end

    it 'updates status to terminated and sets terminated_on' do
      patch "/employees/#{employee.id}",
            params: { employee: { status: 'terminated', terminated_on: '2024-12-31' } },
            headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['status']).to eq('terminated')
      expect(response.parsed_body['terminated_on']).to eq('2024-12-31')
    end

    it 'returns 404 for a non-existent employee' do
      patch '/employees/0', params: { employee: { job_title: 'Ghost' } },
                            headers: admin_headers
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 422 for an invalid status value' do
      patch "/employees/#{employee.id}", params: { employee: { status: 'flying' } },
                                         headers: admin_headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 422 when setting terminated_on without terminated status' do
      patch "/employees/#{employee.id}",
            params: { employee: { terminated_on: Time.zone.today.to_s } },
            headers: admin_headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'clears terminated_on when re-activating a terminated employee' do
      terminated = create(:employee, status: 'terminated', terminated_on: '2024-01-01')
      patch "/employees/#{terminated.id}",
            params: { employee: { status: 'active' } },
            headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['status']).to eq('active')
      expect(response.parsed_body['terminated_on']).to be_nil
      expect(terminated.reload.terminated_on).to be_nil
    end
  end
end
