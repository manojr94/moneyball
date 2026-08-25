# PayAnalytics owns one large aggregate SQL expression; the class length is
# dominated by heredoc SQL text rather than Ruby logic, so the ClassLength cop
# is disabled here rather than splitting the query across files with contrived
# helper classes.
# rubocop:disable Metrics/ClassLength
class PayAnalytics
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

  # Currencies present in the point-in-time snapshot with no exchange rate on
  # or before rate_date. Surfaced in meta so a data gap is visible rather than
  # silently dropping employees from totals.
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

  # Single-pass Postgres aggregate. DISTINCT ON gets the current salary per
  # employee at as_of; a rates CTE gets the latest rate per currency at
  # rate_date; a subunits VALUES table normalizes minor units per ISO 4217
  # exponent; percentile_cont computes the median in SQL rather than loading
  # rows into Ruby.
  AGGREGATE_SQL = <<~SQL.squish.freeze
    WITH rates AS (
      SELECT DISTINCT ON (currency) currency, rate_to_usd FROM exchange_rates
      WHERE effective_date <= %<rate_date>s
      ORDER BY currency, effective_date DESC
    ), rates_with_usd AS (
      SELECT currency, rate_to_usd FROM rates UNION ALL SELECT 'USD', 1
    ), current_salary AS (
      SELECT DISTINCT ON (employee_id) employee_id, amount_minor_units, currency
      FROM salaries WHERE effective_date <= %<as_of>s
      ORDER BY employee_id, effective_date DESC, id DESC
    ), subunits(code, subunit) AS (VALUES %<subunits>s), usd_amounts AS (
      SELECT %<group_col>s AS group_key,
        ROUND(cs.amount_minor_units::numeric / s.subunit * r.rate_to_usd * 100)::bigint
          AS usd_minor_units
      FROM employees
      JOIN current_salary cs ON cs.employee_id = employees.id
      JOIN countries ON countries.code = employees.country_code
      JOIN rates_with_usd r ON r.currency = cs.currency
      JOIN subunits s ON s.code = cs.currency
      WHERE employees.hire_date <= %<as_of>s
        AND (employees.terminated_on IS NULL OR employees.terminated_on > %<as_of>s)
        %<excluded>s %<filters>s
    )
    SELECT group_key, COUNT(*) AS headcount,
      SUM(usd_minor_units) AS total_spend_usd_minor_units,
      MIN(usd_minor_units) AS min_usd_minor_units,
      MAX(usd_minor_units) AS max_usd_minor_units,
      ROUND(AVG(usd_minor_units))::bigint AS avg_usd_minor_units,
      ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY usd_minor_units))::bigint
        AS median_usd_minor_units
    FROM usd_amounts GROUP BY group_key ORDER BY group_key
  SQL

  attr_reader :error, :group_by, :as_of, :rate_date

  def initialize(params = {})
    @group_by  = params[:group_by].to_s
    @as_of     = parse_date(params[:as_of], Date.current)
    @rate_date = parse_date(params[:rate_date], @as_of)
    @filters   = extract_filters(params)
    @error     = validate(params)
  end

  def valid?
    @error.nil?
  end

  def call
    raise 'PayAnalytics called on invalid params' unless valid?

    excluded = unconvertible_currencies
    rows     = connection.select_all(build_aggregate_sql(excluded)).to_a
    { groups: rows.map { |r| present_group(r) }, meta: meta(excluded) }
  end

  private

  def meta(excluded)
    { as_of: @as_of.iso8601, rate_date: @rate_date.iso8601,
      group_by: @group_by, unconvertible_currencies: excluded }
  end

  def unconvertible_currencies
    connection.select_values(format(UNCONVERTIBLE_SQL, as_of: q(@as_of), rate_date: q(@rate_date)))
  end

  def build_aggregate_sql(excluded)
    format(AGGREGATE_SQL,
           as_of: q(@as_of), rate_date: q(@rate_date),
           group_col: GROUPS.fetch(@group_by),
           subunits: subunits_values,
           excluded: excluded_clause(excluded), filters: filter_clauses)
  end

  def excluded_clause(excluded)
    return '' if excluded.empty?

    "AND cs.currency NOT IN (#{excluded.map { |c| q(c) }.join(',')})"
  end

  def filter_clauses
    return '' if @filters.empty?

    @filters.map { |col, val| "AND #{col} = #{q(val)}" }.join(' ')
  end

  # Build a VALUES table from currencies that appear on any salary row so the
  # per-currency exponent join stays a handful of rows. USD is always included
  # so the rates_with_usd branch has a matching subunit.
  def subunits_values
    codes = (Salary.distinct.pluck(:currency).map { |c| c.to_s.upcase } + ['USD']).uniq
    codes.map do |c|
      sub = Money::Currency.find(c)&.subunit_to_unit
      raise ArgumentError, "Unrecognised currency #{c.inspect} — not in money-rails ISO 4217 data" if sub.nil?

      "(#{q(c)}, #{sub})"
    end.join(', ')
  end

  def present_group(row) # rubocop:disable Metrics/AbcSize
    key = row['group_key'].to_s
    { key: key, label: label_lookup[key].presence || key.presence || 'Unconfigured',
      headcount: row['headcount'].to_i,
      total_spend_usd_minor_units: row['total_spend_usd_minor_units'].to_i,
      min_usd_minor_units: row['min_usd_minor_units'].to_i,
      median_usd_minor_units: row['median_usd_minor_units'].to_i,
      avg_usd_minor_units: row['avg_usd_minor_units'].to_i,
      max_usd_minor_units: row['max_usd_minor_units'].to_i, currency: 'USD' }
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

  def parse_date(value, default)
    return default if value.blank?

    Date.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def connection
    ActiveRecord::Base.connection
  end

  def q(value)
    connection.quote(value)
  end
end
# rubocop:enable Metrics/ClassLength
