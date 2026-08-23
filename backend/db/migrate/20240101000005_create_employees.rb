class CreateEmployees < ActiveRecord::Migration[7.1]
  def change
    create_table :employees do |t|
      t.string :employee_number, null: false
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :email, null: false
      t.string :country_code, limit: 2, null: false
      t.references :department, null: false, foreign_key: true
      t.string :job_title, null: false
      t.string :job_level, null: false
      t.date :hire_date, null: false
      t.column :status, :employee_status, null: false, default: 'active'
      t.date :terminated_on
      t.column :created_at, :timestamptz, null: false
      t.column :updated_at, :timestamptz, null: false
    end

    add_index :employees, :employee_number, unique: true
    add_index :employees, :email, unique: true
    add_index :employees, :country_code
    add_index :employees, :status, where: "status = 'active'", name: 'index_employees_on_active_status'
    add_foreign_key :employees, :countries, column: :country_code, primary_key: :code
  end
end
