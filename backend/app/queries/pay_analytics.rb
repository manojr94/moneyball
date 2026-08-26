# PayAnalytics owns one large aggregate SQL expression; the class length is
# dominated by heredoc SQL text rather than Ruby logic, so the ClassLength cop
# is disabled here rather than splitting the query across files with contrived
# helper classes.
class PayAnalytics
  include Analytics::GroupingSupport

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

  def build_aggregate_sql(excluded)
    format(AGGREGATE_SQL,
           as_of: q(@as_of), rate_date: q(@rate_date),
           group_col: group_col,
           subunits: subunits_values,
           excluded: excluded_clause(excluded), filters: filter_clauses)
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
end
