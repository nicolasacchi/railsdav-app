require "rails_helper"

# Regression coverage for the group rename/delete sync-token ordering fix:
# changes to member contacts must be visible to a client that had already synced
# up to the pre-change token (previously they were stamped with a stale token and
# silently lost from incremental sync).
RSpec.describe "CardDAV group sync tokens", type: :request do
  let(:owner) { create(:user, username: "owner") }
  # The user factory already creates a "default" addressbook; reuse it.
  let(:book)  { owner.addressbooks.find_by!(uri: "default") }

  def login
    post login_path, params: { email: owner.email, password: "password123" }
  end

  before do
    # Contact tagged into a group; membership + group are synced from CATEGORIES.
    vcard = Vcard::Parser.generate(full_name: "Member", categories: ["OldName"])
    @contact = create(:contact, addressbook: book, uri: "m1.vcf", vcard_data: vcard)
    @group = book.contact_groups.find_by!(name: "OldName")
    login
  end

  it "stamps group-rename sync changes above the previously-synced token" do
    token_before = book.reload.sync_token

    patch addressbook_group_path(book.uri, @group), params: { name: "NewName" }

    change = book.sync_changes.where(uri: @contact.uri).order(:sync_token).last
    expect(change).to be_present
    expect(change.sync_token).to be > token_before
    # And the addressbook token advanced past it, so a client at token_before
    # will see the change on its next sync-collection.
    expect(book.reload.sync_token).to be >= change.sync_token
  end

  it "rewrites the member's CATEGORIES to the new name" do
    patch addressbook_group_path(book.uri, @group), params: { name: "NewName" }
    parsed = Vcard::Parser.parse(@contact.reload.vcard_data)
    expect(parsed.categories).to include("NewName")
    expect(parsed.categories).not_to include("OldName")
  end
end
