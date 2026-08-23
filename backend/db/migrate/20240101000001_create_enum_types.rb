class CreateEnumTypes < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      CREATE TYPE region_type AS ENUM ('na', 'latam', 'emea', 'apac');
      CREATE TYPE employee_status AS ENUM ('active', 'inactive', 'terminated');
    SQL
  end

  def down
    execute <<~SQL
      DROP TYPE employee_status;
      DROP TYPE region_type;
    SQL
  end
end
