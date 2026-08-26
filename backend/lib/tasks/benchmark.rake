namespace :perf do
  desc 'Benchmark hot query paths against the <500ms target. Requires seeded data.'
  task benchmark: :environment do
    require 'benchmark'

    TARGET_MS  = 500
    RATE_DATE  = Date.new(2025, 1, 1)
    AS_OF_DATE = Date.today
    SEPARATOR  = '-' * 68

    def ms(seconds) = (seconds * 1000).round(1)

    def result_line(label, elapsed_ms)
      icon   = elapsed_ms <= TARGET_MS ? '✓' : '✗'
      status = elapsed_ms <= TARGET_MS ? 'OK' : "OVER TARGET (#{TARGET_MS}ms)"
      format("  %s  %-42s %7.1f ms  %s", icon, label, elapsed_ms, status)
    end

    puts SEPARATOR
    puts "  Moneyball performance benchmark  (target: <#{TARGET_MS} ms)"
    puts "  Dataset: #{Employee.count} employees, #{Salary.count} salaries"
    puts "  as_of=#{AS_OF_DATE}  rate_date=#{RATE_DATE}"
    puts SEPARATOR

    results = {}

    # ── 1. Current salary for all employees (DISTINCT ON hot path) ───────────
    # Simulates the read behind the employee list's salary display.
    t = Benchmark.realtime do
      ActiveRecord::Base.connection.execute(<<~SQL)
        SELECT DISTINCT ON (employee_id) employee_id, amount_minor_units, currency
        FROM salaries
        WHERE effective_date <= '#{AS_OF_DATE}'
        ORDER BY employee_id, effective_date DESC, id DESC
      SQL
    end
    results['current_salary_all'] = ms(t)
    puts result_line('Current salary — all employees', results['current_salary_all'])

    # ── 2. Analytics aggregate: headcount + spend by region ──────────────────
    # Exercises the PayAnalytics CTE chain.
    query = PayAnalytics.new(group_by: 'region', as_of: AS_OF_DATE.to_s,
                             rate_date: RATE_DATE.to_s)
    t = Benchmark.realtime { query.call }
    results['analytics_region'] = ms(t)
    puts result_line('Analytics — headcount+spend by region', results['analytics_region'])

    # ── 3. Analytics aggregate: headcount + spend by department ──────────────
    query2 = PayAnalytics.new(group_by: 'department', as_of: AS_OF_DATE.to_s,
                              rate_date: RATE_DATE.to_s)
    t = Benchmark.realtime { query2.call }
    results['analytics_dept'] = ms(t)
    puts result_line('Analytics — headcount+spend by department', results['analytics_dept'])

    # ── 4. Band resolution — single employee ─────────────────────────────────
    # BandResolver is always called per-employee; the interesting metric is
    # one resolution, not an N-employee loop. Picks a random active employee.
    sample_emp = Employee.active.order('RANDOM()').first
    t = Benchmark.realtime do
      BandResolver.resolve(employee: sample_emp, on_date: AS_OF_DATE, rate_date: RATE_DATE)
    end
    results['band_resolution_single'] = ms(t)
    puts result_line('Band resolution — single employee', results['band_resolution_single'])

    # ── 5. Employee index query (first page, default sort) ────────────────────
    t = Benchmark.realtime do
      EmployeeQuery.new({}).call
    end
    results['employee_index'] = ms(t)
    puts result_line('Employee index — first page, default sort', results['employee_index'])

    puts SEPARATOR
    passed = results.count { |_, v| v <= TARGET_MS }
    total  = results.size
    puts "  #{passed}/#{total} paths within target"
    puts SEPARATOR

    if results.any? { |_, v| v > TARGET_MS }
      puts "\n  Paths over target — consider EXPLAIN ANALYZE:"
      results.each { |k, v| puts "    #{k}: #{v} ms" if v > TARGET_MS }
      puts
    end
  end
end
