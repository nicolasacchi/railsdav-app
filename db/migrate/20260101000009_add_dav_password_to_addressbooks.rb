class AddDavPasswordToAddressbooks < ActiveRecord::Migration[8.1]
  def up
    add_column :addressbooks, :dav_password, :string
    Addressbook.reset_column_information
    Addressbook.where(dav_password: nil).find_each do |ab|
      ab.update_column(:dav_password, SecureRandom.urlsafe_base64(18))
    end
  end

  def down
    remove_column :addressbooks, :dav_password
  end
end
