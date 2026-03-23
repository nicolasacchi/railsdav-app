class ContactGroup < ApplicationRecord
  belongs_to :addressbook
  belongs_to :group_contact, class_name: "Contact", optional: true
  has_many :contact_group_memberships, dependent: :destroy
  has_many :contacts, through: :contact_group_memberships

  validates :name, presence: true, uniqueness: { scope: :addressbook_id }

  scope :ordered, -> { order(:name) }
end
