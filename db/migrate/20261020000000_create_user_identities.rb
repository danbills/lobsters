class CreateUserIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :user_identities do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :issuer, null: false
      t.string :subject, null: false
      t.string :email, limit: 100, collation: "NOCASE"
      t.datetime :last_login_at
      t.timestamps
    end
    add_index :user_identities, [:issuer, :subject], unique: true
  end
end
