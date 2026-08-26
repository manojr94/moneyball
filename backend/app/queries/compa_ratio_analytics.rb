# CompaRatioAnalytics mirrors PayAnalytics in structure: one unconvertible-currency probe
# and one grouped aggregate query. The ClassLength cop is disabled for the same reason as
# PayAnalytics — the bulk of the file is SQL heredocs, not Ruby logic.
# rubocop:disable Metrics/ClassLength
class CompaRatioAnalytics
  include Analytics::GroupingSupport

  # LEFT JOIN salary_bands so employees with no band still count toward headcount.
  # LEFT JOIN rates_with_usd and subunits for the band currency so a band whose
  # currency has no rate at rate_date surfaces as unresolved rather than causing
  # a divide-by-zero or NULL arithmetic bleed.
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
    ), subunits(code, subunit) AS (VALUES %<subunits>s),
    usd_amounts AS (
      SELECT %<group_col>s AS group_key,
        ROUND(cs.amount_minor_units::numeric / ss.subunit * sr.rate_to_usd * 100)::bigint
          AS salary_usd,
        ROUND(sb.min_minor_units::numeric / bs.subunit * br.rate_to_usd * 100)::bigint
          AS band_min_usd,
        ROUND(sb.mid_minor_units::numeric / bs.subunit * br.rate_to_usd * 100)::bigint
          AS band_mid_usd,
        ROUND(sb.max_minor_units::numeric / bs.subunit * br.rate_to_usd * 100)::bigint
          AS band_max_usd,
        sb.id AS band_id,
        br.rate_to_usd AS band_rate
      FROM employees
      JOIN current_salary cs ON cs.employee_id = employees.id
      JOIN countries ON countries.code = employees.country_code
      JOIN rates_with_usd sr ON sr.currency = cs.currency
      JOIN subunits ss ON ss.code = cs.currency
      LEFT JOIN salary_bands sb
        ON sb.pay_zone_id = countries.pay_zone_id
        AND sb.job_title = employees.job_title
        AND sb.job_level = employees.job_level
        AND sb.effective_from <= %<as_of>s
        AND (sb.effective_to IS NULL OR sb.effective_to > %<as_of>s)
      LEFT JOIN rates_with_usd br ON br.currency = sb.currency
      LEFT JOIN subunits bs ON bs.code = sb.currency
      WHERE employees.status = 'active'
        AND employees.hire_date <= %<as_of>s
        AND (employees.terminated_on IS NULL OR employees.terminated_on > %<as_of>s)
        %<excluded>s %<filters>s
    )
    SELECT group_key,
      COUNT(*) AS headcount,
      COUNT(CASE WHEN band_id IS NOT NULL AND band_rate IS NOT NULL THEN 1 END)
        AS covered_headcount,
      ROUND(AVG(
        CASE WHEN band_id IS NOT NULL AND band_rate IS NOT NULL AND band_mid_usd > 0
          THEN salary_usd::numeric / band_mid_usd END
      )::numeric, 4) AS avg_compa_ratio,
      COUNT(CASE WHEN band_id IS NULL OR band_rate IS NULL THEN 1 END) AS unresolved,
      COUNT(CASE WHEN band_id IS NOT NULL AND band_rate IS NOT NULL
                  AND salary_usd < band_min_usd THEN 1 END) AS below_count,
      COUNT(CASE WHEN band_id IS NOT NULL AND band_rate IS NOT NULL
                  AND salary_usd >= band_min_usd AND salary_usd <= band_max_usd THEN 1 END)
        AS within_count,
      COUNT(CASE WHEN band_id IS NOT NULL AND band_rate IS NOT NULL
                  AND salary_usd > band_max_usd THEN 1 END) AS above_count
    FROM usd_amounts
    GROUP BY group_key
    ORDER BY group_key
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
    raise 'CompaRatioAnalytics called on invalid params' unless valid?

    excluded = unconvertible_currencies
    rows     = connection.select_all(build_aggregate_sql(excluded)).to_a
    uncovered = uncovered_count

    { groups: rows.map { |r| present_group(r) },
      meta: meta(excluded, uncovered) }
  end

  private

  def meta(excluded, uncovered)
    { as_of: @as_of.iso8601, rate_date: @rate_date.iso8601,
      group_by: @group_by,
      unconvertible_currencies: excluded,
      uncovered_combinations: uncovered }
  end

  # Count of (pay_zone, job_title, job_level) combos for active employees where no
  # band covers today. Used in meta only; the full list is the band_coverage endpoint.
  # rubocop:disable Metrics/MethodLength
  def uncovered_count
    connection.select_value(<<~SQL.squish)
      SELECT COUNT(DISTINCT (countries.pay_zone_id, employees.job_title, employees.job_level))
      FROM employees
      JOIN countries ON countries.code = employees.country_code
      WHERE employees.status = 'active'
        AND employees.hire_date <= #{q(@as_of)}
        AND (employees.terminated_on IS NULL OR employees.terminated_on > #{q(@as_of)})
        AND countries.pay_zone_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM salary_bands sb
          WHERE sb.pay_zone_id = countries.pay_zone_id
            AND sb.job_title = employees.job_title
            AND sb.job_level = employees.job_level
            AND sb.effective_from <= #{q(@as_of)}
            AND (sb.effective_to IS NULL OR sb.effective_to > #{q(@as_of)})
        )
    SQL
  end
  # rubocop:enable Metrics/MethodLength

  def build_aggregate_sql(excluded)
    format(AGGREGATE_SQL,
           as_of: q(@as_of),
           rate_date: q(@rate_date),
           group_col: group_col,
           subunits: subunits_values,
           excluded: excluded_clause(excluded),
           filters: filter_clauses)
  end

  # rubocop:disable Metrics/AbcSize
  def subunits_values
    @subunits_values ||= begin
      salary_codes = Salary.distinct.pluck(:currency).map { |c| c.to_s.upcase }
      band_codes   = SalaryBand.distinct.pluck(:currency).map { |c| c.to_s.upcase }
      codes = (salary_codes + band_codes + ['USD']).uniq
      codes.map do |c|
        sub = Money::Currency.find(c)&.subunit_to_unit
        raise ArgumentError, "Unrecognised currency #{c.inspect} — not in money-rails ISO 4217 data" if sub.nil?

        "(#{q(c)}, #{sub})"
      end.join(', ')
    end
  end
  # rubocop:enable Metrics/AbcSize

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def present_group(row)
    key = row['group_key'].to_s
    ratio = row['avg_compa_ratio']
    { key: key,
      label: label_lookup[key].presence || key.presence || 'Unconfigured',
      headcount: row['headcount'].to_i,
      covered_headcount: row['covered_headcount'].to_i,
      avg_compa_ratio: ratio ? format('%.4f', ratio.to_f) : nil,
      below: row['below_count'].to_i,
      within: row['within_count'].to_i,
      above: row['above_count'].to_i,
      unresolved: row['unresolved'].to_i }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
# rubocop:enable Metrics/ClassLength
