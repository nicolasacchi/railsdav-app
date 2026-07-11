require "rails_helper"

# Per-tenant API tokens: a token issued to one user pins the tenant and cannot
# read another tenant's data, even by passing a different ?username=.
RSpec.describe "Api per-tenant token auth", type: :request do
  let(:alice) { create(:user, username: "alice") }
  let(:bob)   { create(:user, username: "bob") }

  def make_contact(user:, phone:, name:)
    book = user.addressbooks.first
    vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-#{SecureRandom.hex(4)}\r\nFN:#{name}\r\nTEL:#{phone}\r\nEND:VCARD\r\n"
    create(:contact, addressbook: book, uri: "#{SecureRandom.uuid}.vcf", vcard_data: vcard)
  end

  before do
    # No global token configured — per-tenant tokens must still work.
    ENV.delete("CALLSCREEN_API_TOKEN")
    ENV.delete("CALLSCREEN_API_USERNAME")
  end

  it "authenticates with a per-tenant token and pins the tenant" do
    token = alice.regenerate_api_token!
    make_contact(user: alice, phone: "+393331234567", name: "AliceFriend")

    get "/api/contact_lookup", params: { phone: "+393331234567" },
        headers: { "Authorization" => "Bearer #{token}" }

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include("match" => true, "name" => "AliceFriend")
  end

  it "ignores ?username= and never reads another tenant's book" do
    token = alice.regenerate_api_token!
    make_contact(user: bob, phone: "+393339999999", name: "BobSecret")

    # Alice's token tries to look up a number that only exists in Bob's book,
    # explicitly asking for bob via ?username=. It must resolve to Alice.
    get "/api/contact_lookup", params: { phone: "+393339999999", username: "bob" },
        headers: { "Authorization" => "Bearer #{token}" }

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include("match" => false)
  end

  it "rejects a revoked token" do
    token = alice.regenerate_api_token!
    alice.revoke_api_token!

    get "/api/contact_lookup", params: { phone: "+393331234567" },
        headers: { "Authorization" => "Bearer #{token}" }

    # No global token and no valid per-tenant token ⇒ service unavailable.
    expect(response).to have_http_status(:service_unavailable)
  end

  it "does not authenticate a blank token against a null digest" do
    alice # created, but no token issued
    get "/api/contact_lookup", params: { phone: "+393331234567" },
        headers: { "Authorization" => "Bearer " }

    expect(response).not_to have_http_status(:ok)
  end
end
