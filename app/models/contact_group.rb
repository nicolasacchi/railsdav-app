class ContactGroup < ApplicationRecord
  belongs_to :addressbook
  belongs_to :group_contact, class_name: "Contact", optional: true
  has_many :contact_group_memberships, dependent: :destroy
  has_many :contacts, through: :contact_group_memberships

  validates :name, presence: true, uniqueness: { scope: :addressbook_id }

  scope :ordered, -> { order(:name) }

  def update_member_vcards
    contacts.individuals.find_each do |contact|
      parsed = Vcard::Parser.parse(contact.vcard_data)
      next unless parsed

      categories = parsed.categories || []
      new_categories = yield(categories)
      next if new_categories == categories

      new_vcard = Vcard::Parser.update_categories(contact.vcard_data, new_categories)
      contact.update!(vcard_data: new_vcard)
      # record_sync_change! increments the sync token BEFORE stamping the row, so
      # the change is > the token any already-synced client holds. Stamping with
      # the pre-increment token would make the change invisible to sync-collection.
      addressbook.record_sync_change!(uri: contact.uri, change_type: "modified")
    end
  end
end
