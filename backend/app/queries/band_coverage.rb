class BandCoverage
  ACTIVE_POPULATION = <<~SQL.squish.freeze
    employees.status = 'active'
    AND employees.hire_date <= CURRENT_DATE
    AND (employees.terminated_on IS NULL OR employees.terminated_on > CURRENT_DATE)
  SQL

  NO_BAND_EXISTS = <<~SQL.squish.freeze
    NOT EXISTS (
      SELECT 1 FROM salary_bands sb
      WHERE sb.pay_zone_id = countries.pay_zone_id
        AND sb.job_title = employees.job_title
        AND sb.job_level = employees.job_level
        AND sb.effective_from <= CURRENT_DATE
        AND (sb.effective_to IS NULL OR sb.effective_to > CURRENT_DATE)
    )
  SQL

  # Returns { uncovered: [...], unzoned: [...] }
  def call
    { uncovered: uncovered_combinations, unzoned: unzoned_combinations }
  end

  private

  # rubocop:disable Metrics/MethodLength
  def uncovered_combinations
    connection.select_all(<<~SQL.squish).map do |row|
      SELECT countries.pay_zone_id,
             pay_zones.name AS pay_zone_name,
             employees.job_title,
             employees.job_level,
             COUNT(*) AS employee_count
      FROM employees
      JOIN countries ON countries.code = employees.country_code
      JOIN pay_zones ON pay_zones.id = countries.pay_zone_id
      WHERE #{ACTIVE_POPULATION}
        AND countries.pay_zone_id IS NOT NULL
        AND #{NO_BAND_EXISTS}
      GROUP BY countries.pay_zone_id, pay_zones.name, employees.job_title, employees.job_level
      ORDER BY pay_zones.name, employees.job_title, employees.job_level
    SQL
      { pay_zone_id: row['pay_zone_id'],
        pay_zone_name: row['pay_zone_name'],
        job_title: row['job_title'],
        job_level: row['job_level'],
        employee_count: row['employee_count'].to_i }
    end
  end
  # rubocop:enable Metrics/MethodLength

  # rubocop:disable Metrics/MethodLength
  def unzoned_combinations
    connection.select_all(<<~SQL.squish).map do |row|
      SELECT employees.country_code,
             employees.job_title,
             employees.job_level,
             COUNT(*) AS employee_count
      FROM employees
      JOIN countries ON countries.code = employees.country_code
      WHERE #{ACTIVE_POPULATION}
        AND countries.pay_zone_id IS NULL
      GROUP BY employees.country_code, employees.job_title, employees.job_level
      ORDER BY employees.country_code, employees.job_title, employees.job_level
    SQL
      { country_code: row['country_code'],
        job_title: row['job_title'],
        job_level: row['job_level'],
        employee_count: row['employee_count'].to_i }
    end
  end
  # rubocop:enable Metrics/MethodLength

  def connection
    ActiveRecord::Base.connection
  end
end
