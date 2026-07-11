module ApplicationHelper
  ENCRYPTION_LABELS = {
    encrypted_blob:  "Encrypted blob",
    encrypted_vcard: "Encrypted vCard",
    bootstrap_vcard: "E2E bootstrap marker",
    plaintext_vcard: "Plaintext vCard",
    unknown:         "Unknown"
  }.freeze

  # Run the probabilistic classifier over a contact's stored payload so the UI
  # can show WHAT the server thinks it holds (it never decrypts) and HOW sure it
  # is. Surfaces the classifier's rich output that was previously computed but
  # only ever consumed as a boolean.
  def contact_encryption_detail(contact)
    E2ee::Detection.classify(contact.vcard_data)
  end

  def encryption_classification_label(classification)
    ENCRYPTION_LABELS.fetch(classification) { classification.to_s.tr("_", " ").capitalize }
  end

  def encryption_confidence_percent(probability)
    "#{(probability.to_f * 100).round(1)}%"
  end
end
