class CreateInvitations < ActiveRecord::Migration[7.1]
  def change
    create_table :invitations do |t|
      t.string   :token, null: false
      t.datetime :used_at
      t.timestamps
    end
    add_index :invitations, :token, unique: true
  end
end
