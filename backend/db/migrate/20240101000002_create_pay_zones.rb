class CreatePayZones < ActiveRecord::Migration[7.1]
  def change
    create_table :pay_zones do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.timestamps
    end

    add_index :pay_zones, :slug, unique: true
  end
end
