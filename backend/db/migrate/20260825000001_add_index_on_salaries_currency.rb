class AddIndexOnSalariesCurrency < ActiveRecord::Migration[7.1]
  def change
    add_index :salaries, :currency
  end
end
