class HashDavPasswords < ActiveRecord::Migration[8.0]
  def up
    add_column :addressbooks, :dav_password_digest, :string

    Addressbook.reset_column_information
    Addressbook.where.not(dav_password: nil).find_each do |ab|
      ab.update_column(:dav_password_digest, BCrypt::Password.create(ab.dav_password))
    end

    remove_column :addressbooks, :dav_password
  end

  def down
    add_column :addressbooks, :dav_password, :string
    remove_column :addressbooks, :dav_password_digest
  end
end
