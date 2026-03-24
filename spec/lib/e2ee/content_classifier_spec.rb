require "rails_helper"
require "e2ee/content_classifier"

RSpec.describe E2ee::ContentClassifier do
  subject(:classifier) { described_class.new }

  let(:simple_vcard) do
    "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:test-uid\r\nFN:John Doe\r\nN:Doe;John;;;\r\nEND:VCARD\r\n"
  end

  let(:vcard_v4) do
    "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:v4-uid\r\nFN:Jane Smith\r\nANNIVERSARY:20200101\r\nEND:VCARD\r\n"
  end

  let(:bootstrap_vcard) do
    "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:system-bootstrap@e2e-carddav\r\n" \
    "FN:E2EE Bootstrap\r\nCATEGORIES:SYSTEM,BOOTSTRAP\r\n" \
    "X-E2EE-ALGORITHM:xchacha20-poly1305-v1\r\nX-E2EE-KDF:argon2id\r\n" \
    "X-E2EE-SALT:dGVzdHNhbHQ=\r\nX-E2EE-VERSION:1\r\nEND:VCARD\r\n"
  end

  let(:encrypted_vcard_wrapper) do
    "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:normal-contact-uid\r\n" \
    "FN:Encrypted Contact\r\n" \
    "X-E2EE-ALGORITHM:xchacha20-poly1305-v1\r\n" \
    "X-E2EE-PAYLOAD:dGhpcyBpcyBlbmNyeXB0ZWQgZGF0YQ==\r\n" \
    "END:VCARD\r\n"
  end

  let(:encrypted_blob_256) { SecureRandom.random_bytes(256) }
  let(:encrypted_blob_1k) { SecureRandom.random_bytes(1024) }

  describe "#classify" do
    context "plaintext vCards" do
      it "classifies vCard 3.0 as :plaintext_vcard" do
        result = classifier.classify(simple_vcard)
        expect(result[:classification]).to eq(:plaintext_vcard)
        expect(result[:score]).to be > 8.0
        expect(result[:probability]).to be > 0.99
      end

      it "classifies vCard 4.0 as :plaintext_vcard" do
        result = classifier.classify(vcard_v4)
        expect(result[:classification]).to eq(:plaintext_vcard)
      end

      it "returns feature breakdown" do
        result = classifier.classify(simple_vcard)
        expect(result[:breakdown]).to include(:magic_bytes, :entropy, :ascii_ratio,
                                              :vcard_tokens, :line_structure)
        expect(result[:breakdown][:magic_bytes]).to eq(8.0)
        expect(result[:breakdown][:vcard_tokens]).to eq(5.0)
      end
    end

    context "bootstrap vCard" do
      it "classifies bootstrap vCard as :bootstrap_vcard" do
        result = classifier.classify(bootstrap_vcard)
        expect(result[:classification]).to eq(:bootstrap_vcard)
      end

      it "has high confidence for bootstrap" do
        result = classifier.classify(bootstrap_vcard)
        expect(result[:score]).to be > 20.0
        expect(result[:breakdown][:bootstrap_uid]).to eq(10.0)
        expect(result[:breakdown][:e2ee_markers]).to eq(6.0)
      end
    end

    context "encrypted vCard wrapper" do
      it "classifies vCard with X-E2EE-ALGORITHM but normal UID as :encrypted_vcard" do
        result = classifier.classify(encrypted_vcard_wrapper)
        expect(result[:classification]).to eq(:encrypted_vcard)
      end
    end

    context "encrypted binary blobs" do
      it "classifies 256 random bytes as :encrypted_blob" do
        result = classifier.classify(encrypted_blob_256)
        expect(result[:classification]).to eq(:encrypted_blob)
        expect(result[:score]).to be < -5.0
      end

      it "classifies 1KB random bytes as :encrypted_blob" do
        result = classifier.classify(encrypted_blob_1k)
        expect(result[:classification]).to eq(:encrypted_blob)
      end

      it "detects high entropy in random bytes" do
        result = classifier.classify(encrypted_blob_1k)
        expect(result[:features][:entropy]).to be > 7.0
      end

      it "detects low ASCII ratio in random bytes" do
        result = classifier.classify(encrypted_blob_1k)
        expect(result[:features][:ascii_ratio]).to be < 0.5
      end
    end

    context "edge cases" do
      it "returns :unknown for nil" do
        result = classifier.classify(nil)
        expect(result[:classification]).to eq(:unknown)
        expect(result[:probability]).to eq(0.5)
      end

      it "returns :unknown for empty string" do
        result = classifier.classify("")
        expect(result[:classification]).to eq(:unknown)
      end

      it "classifies non-vCard text without magic bytes as :encrypted_blob" do
        # Any content without BEGIN:VCARD is treated as opaque/encrypted
        result = classifier.classify("This is just plain text, not a vCard.")
        expect(result[:classification]).to eq(:encrypted_blob)
      end
    end

    context "entropy calculation" do
      it "computes low entropy for repetitive text" do
        result = classifier.classify("AAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        expect(result[:features][:entropy]).to be < 1.0
      end

      it "computes moderate entropy for natural text vCard" do
        result = classifier.classify(simple_vcard)
        expect(result[:features][:entropy]).to be_between(3.0, 6.0)
      end
    end
  end

  describe "#encrypted?" do
    it "returns true for encrypted blob" do
      expect(classifier.encrypted?(encrypted_blob_256)).to be true
    end

    it "returns true for encrypted vCard wrapper" do
      expect(classifier.encrypted?(encrypted_vcard_wrapper)).to be true
    end

    it "returns false for plaintext vCard" do
      expect(classifier.encrypted?(simple_vcard)).to be false
    end

    it "returns false for bootstrap vCard" do
      expect(classifier.encrypted?(bootstrap_vcard)).to be false
    end

    it "returns false for nil" do
      expect(classifier.encrypted?(nil)).to be false
    end
  end

  describe "#bootstrap?" do
    it "returns true for bootstrap vCard" do
      expect(classifier.bootstrap?(bootstrap_vcard)).to be true
    end

    it "returns false for plaintext vCard" do
      expect(classifier.bootstrap?(simple_vcard)).to be false
    end

    it "returns false for encrypted blob" do
      expect(classifier.bootstrap?(encrypted_blob_256)).to be false
    end

    it "returns false for encrypted vCard wrapper" do
      expect(classifier.bootstrap?(encrypted_vcard_wrapper)).to be false
    end
  end

  describe "#plaintext_vcard?" do
    it "returns true for normal vCard" do
      expect(classifier.plaintext_vcard?(simple_vcard)).to be true
    end

    it "returns false for bootstrap (classified separately)" do
      expect(classifier.plaintext_vcard?(bootstrap_vcard)).to be false
    end

    it "returns false for encrypted blob" do
      expect(classifier.plaintext_vcard?(encrypted_blob_256)).to be false
    end
  end
end
