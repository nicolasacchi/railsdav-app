module E2ee
  module Detection
    BOOTSTRAP_UID = "system-bootstrap@e2e-carddav".freeze

    def self.encrypted?(data)
      return false if data.nil? || data.empty?
      !data.b.start_with?("BEGIN:VCARD")
    end

    def self.bootstrap_vcard?(data)
      return false if encrypted?(data)
      data.include?("UID:#{BOOTSTRAP_UID}")
    end
  end
end
