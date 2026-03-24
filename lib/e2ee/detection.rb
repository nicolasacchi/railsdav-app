require_relative "content_classifier"

module E2ee
  module Detection
    BOOTSTRAP_UID = "system-bootstrap@e2e-carddav".freeze

    def self.classifier
      @classifier ||= ContentClassifier.new
    end

    def self.classify(data)
      classifier.classify(data)
    end

    def self.encrypted?(data)
      classifier.encrypted?(data)
    end

    def self.bootstrap_vcard?(data)
      classifier.bootstrap?(data)
    end
  end
end
