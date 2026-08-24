class AddUsersAndAuth < ActiveRecord::Migration[7.1]
  def up
    execute "CREATE TYPE user_role AS ENUM ('hr_admin', 'viewer');"

    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :name, null: false
      t.column :role, :user_role, null: false, default: 'viewer'
      t.boolean :active, null: false, default: true
      t.integer :token_version, null: false, default: 0
      t.timestamptz :last_sign_in_at

      t.timestamps
    end

    add_index :users, :email, unique: true

    # Nullify phantom created_by_id values recorded before users existed,
    # then enforce the foreign key constraint going forward.
    execute "UPDATE salaries SET created_by_id = NULL WHERE created_by_id IS NOT NULL " \
            "AND created_by_id NOT IN (SELECT id FROM users);"

    add_foreign_key :salaries, :users, column: :created_by_id
  end

  def down
    remove_foreign_key :salaries, column: :created_by_id
    drop_table :users
    execute "DROP TYPE user_role;"
  end
end
