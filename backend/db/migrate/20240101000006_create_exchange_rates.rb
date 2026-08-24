class CreateExchangeRates < ActiveRecord::Migration[7.1]
  def change
    create_table :exchange_rates do |t|
      t.string :currency, limit: 3, null: false
      t.decimal :rate_to_usd, precision: 18, scale: 8, null: false
      t.date :effective_date, null: false
      t.datetime :created_at, null: false
    end

    add_index :exchange_rates, %i[currency effective_date],
              order: { effective_date: :desc },
              name: 'index_exchange_rates_on_currency_and_effective_date'
  end
end
