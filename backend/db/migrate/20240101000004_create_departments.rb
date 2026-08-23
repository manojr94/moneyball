class CreateDepartments < ActiveRecord::Migration[7.1]
  def change
    create_table :departments do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.timestamps
    end

    add_index :departments, :slug, unique: true
  end
end
