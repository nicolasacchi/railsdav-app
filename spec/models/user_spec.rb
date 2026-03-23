require "rails_helper"

RSpec.describe User, type: :model do
  describe "validations" do
    it "requires a username or auto-generates one" do
      user = User.new(email: "test@example.com", password: "password123")
      expect(user).to be_valid
      expect(user.username).to be_present
    end

    it "requires a unique username (case-insensitive)" do
      create(:user, username: "alice")
      user = User.new(username: "Alice", email: "another@example.com", password: "password123")
      expect(user).not_to be_valid
      expect(user.errors[:username]).to include("has already been taken")
    end

    it "requires username to contain only letters, numbers, hyphens, underscores" do
      user = User.new(username: "bad user!", email: "test@example.com", password: "password123")
      expect(user).not_to be_valid
      expect(user.errors[:username]).to be_present
    end

    it "accepts valid usernames" do
      user = User.new(username: "alice-bob_123", email: "alice@example.com", password: "password123")
      expect(user).to be_valid
    end
  end

  describe "username auto-generation" do
    it "generates username from email prefix" do
      user = create(:user, email: "john.doe@example.com", username: "")
      expect(user.username).to eq("john.doe")
    end

    it "handles collision by appending numbers" do
      create(:user, username: "alice", email: "alice@one.com")
      user = create(:user, email: "alice@two.com", username: "")
      expect(user.username).to eq("alice-1")
    end

    it "replaces non-allowed characters" do
      user = create(:user, email: "hello+world@example.com", username: "")
      expect(user.username).to eq("hello-world")
    end
  end

  describe "has_secure_password" do
    it "authenticates with correct password" do
      user = create(:user, password: "secret123")
      expect(user.authenticate("secret123")).to eq(user)
    end

    it "rejects wrong password" do
      user = create(:user, password: "secret123")
      expect(user.authenticate("wrong")).to be_falsey
    end
  end

  describe "after_create callbacks" do
    it "creates a default addressbook" do
      user = create(:user)
      expect(user.addressbooks.count).to eq(1)
      ab = user.addressbooks.first
      expect(ab.uri).to eq("default")
      expect(ab.displayname).to eq("Contacts")
    end

    it "claims pending invitations matching email" do
      ab = create(:addressbook)
      share = create(:addressbook_share, :pending_new_user, addressbook: ab, invited_email: "newbie@example.com")

      user = create(:user, email: "newbie@example.com")
      share.reload

      expect(share.user_id).to eq(user.id)
      expect(share.status).to eq("accepted")
      expect(share.invitation_token).to be_nil
    end
  end

  describe "email validation" do
    it "requires email" do
      user = build(:user, email: nil)
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("can't be blank")
    end

    it "accepts valid emails" do
      user = build(:user, email: "test@example.com")
      expect(user).to be_valid
    end

    it "rejects invalid emails" do
      user = build(:user, email: "not-an-email")
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it "requires unique email (case-insensitive)" do
      create(:user, email: "test@example.com")
      user = build(:user, email: "TEST@example.com")
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("has already been taken")
    end
  end

  describe "associations" do
    it "destroys addressbooks on user deletion" do
      user = create(:user)
      expect { user.destroy }.to change(Addressbook, :count).by(-1)
    end
  end

  describe "password reset token (Rails built-in)" do
    let(:user) { create(:user) }

    it "generates a signed reset token" do
      token = user.password_reset_token
      expect(token).to be_present
    end

    it "finds user by valid token" do
      token = user.password_reset_token
      found = User.find_by_password_reset_token(token)
      expect(found).to eq(user)
    end

    it "returns nil for invalid token" do
      found = User.find_by_password_reset_token("bogus")
      expect(found).to be_nil
    end

    it "invalidates token after password change" do
      token = user.password_reset_token
      user.update!(password: "newpassword456")
      found = User.find_by_password_reset_token(token)
      expect(found).to be_nil
    end
  end

  describe "#admin?" do
    let(:user) { create(:user) }

    it "returns true when admin is true" do
      user.update!(admin: true)
      expect(user.admin?).to be true
    end

    it "returns false when admin is false" do
      expect(user.admin?).to be false
    end
  end
end
