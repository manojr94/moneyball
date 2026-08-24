class CreateSalaries < ActiveRecord::Migration[7.1]
  def change
    create_table :salaries do |t|
      t.references :employee, null: false, foreign_key: true
      t.bigint :amount_minor_units, null: false
      t.string :currency, limit: 3, null: false
      t.date :effective_date, null: false
      t.string :reason, null: false
      t.bigint :created_by_id

      t.timestamps
    end

    add_index :salaries, %i[employee_id effective_date],
              order: { effective_date: :desc },
              name: 'index_salaries_on_employee_id_and_effective_date'
  end
end
