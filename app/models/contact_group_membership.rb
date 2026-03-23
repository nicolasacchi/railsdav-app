class ContactGroupMembership < ApplicationRecord
  belongs_to :contact
  belongs_to :contact_group

  validates :contact_group_id, uniqueness: { scope: :contact_id }
end
