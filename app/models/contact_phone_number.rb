class ContactPhoneNumber < ApplicationRecord
  belongs_to :contact

  validates :e164, presence: true
end
