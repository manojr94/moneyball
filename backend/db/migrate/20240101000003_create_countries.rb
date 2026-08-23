class CreateCountries < ActiveRecord::Migration[7.1]
  def change
    create_table :countries, primary_key: :code, id: :string, force: :cascade do |t|
      t.string :name, null: false
      t.string :default_currency, limit: 3, null: false
      t.references :pay_zone, foreign_key: true
      t.column :region, :region_type, null: false
      t.boolean :needs_review, null: false, default: false
      t.column :created_at, :timestamptz, null: false
      t.column :updated_at, :timestamptz, null: false
    end
  end
end
