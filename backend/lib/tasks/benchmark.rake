namespace :perf do
  desc 'Benchmark hot query paths against the <500ms target. Requires seeded data.'
  task benchmark: :environment do
    require 'benchmark'

    target_ms  = 500
    rate_date  = Date.new(2025, 1, 1)
    as_of_date = Time.zone.today
    separator  = '-' * 68

    ms = ->(seconds) { (seconds * 1000).round(1) }
    result_line = lambda do |label, elapsed_ms|
      icon   = elapsed_ms <= target_ms ? '✓' : '✗'
      status = elapsed_ms <= target_ms ? 'OK' : "OVER TARGET (#{target_ms}ms)"
      "  #{icon}  #{label.ljust(42)} #{format('%<ms>7.1f', ms: elapsed_ms)} ms  #{status}"
    end

    puts separator
    puts "  Moneyball performance benchmark  (target: <#{target_ms} ms)"
    puts "  Dataset: #{Employee.count} employees, #{Salary.count} salaries"
    puts "  as_of=#{as_of_date}  rate_date=#{rate_date}"
    puts separator

    results = {}

    # ── 1. Current salary for all employees (DISTINCT ON hot path) ───────────
    # Simulates the read behind the employee list's salary display.
    t = Benchmark.realtime do
      conn        = ActiveRecord::Base.connection
      quoted_date = conn.quote(as_of_date)
      conn.execute(<<~SQL.squish)
        SELECT DISTINCT ON (employee_id) employee_id, amount_minor_units, currency
        FROM salaries
        WHERE effective_date <= #{quoted_date}
        ORDER BY employee_id, effective_date DESC, id DESC
      SQL
    end
    results['current_salary_all'] = ms.call(t)
    puts result_line.call('Current salary — all employees', results['current_salary_all'])

    # ── 2. Analytics aggregate: headcount + spend by region ──────────────────
    # Exercises the PayAnalytics CTE chain.
    query = PayAnalytics.new(group_by: 'region', as_of: as_of_date.to_s,
                             rate_date: rate_date.to_s)
    t = Benchmark.realtime { query.call }
    results['analytics_region'] = ms.call(t)
    puts result_line.call('Analytics — headcount+spend by region', results['analytics_region'])

    # ── 3. Analytics aggregate: headcount + spend by department ──────────────
    query2 = PayAnalytics.new(group_by: 'department', as_of: as_of_date.to_s,
                              rate_date: rate_date.to_s)
    t = Benchmark.realtime { query2.call }
    results['analytics_dept'] = ms.call(t)
    puts result_line.call('Analytics — headcount+spend by department', results['analytics_dept'])

    # ── 4. Band resolution — single employee ─────────────────────────────────
    # BandResolver is always called per-employee; the interesting metric is
    # one resolution, not an N-employee loop. Picks a random active employee.
    sample_emp = Employee.active.order('RANDOM()').first
    t = Benchmark.realtime do
      BandResolver.resolve(employee: sample_emp, on_date: as_of_date, rate_date: rate_date)
    end
    results['band_resolution_single'] = ms.call(t)
    puts result_line.call('Band resolution — single employee', results['band_resolution_single'])

    # ── 5. Employee index query (first page, default sort) ────────────────────
    t = Benchmark.realtime do
      EmployeeQuery.new({}).call
    end
    results['employee_index'] = ms.call(t)
    puts result_line.call('Employee index — first page, default sort', results['employee_index'])

    puts separator
    passed = results.count { |_, v| v <= target_ms }
    total  = results.size
    puts "  #{passed}/#{total} paths within target"
    puts separator

    if results.any? { |_, v| v > target_ms }
      puts "\n  Paths over target — consider EXPLAIN ANALYZE:"
      results.each { |k, v| puts "    #{k}: #{v} ms" if v > target_ms }
      puts
    end
  end
end
