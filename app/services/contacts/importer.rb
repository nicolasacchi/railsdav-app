require "csv"
require "json"

module Contacts
  class Importer
    class UnsupportedFormat < StandardError; end
    class ParseError < StandardError; end

    ImportResult = Data.define(:imported, :updated, :failed, :errors)

    HEADER_ALIASES = {
      "name" => "full_name",
      "email" => "email_1",
      "phone" => "phone_1",
      "company" => "organization",
      "bday" => "birthday",
      "website" => "url_1",
      "url" => "url_1",
      "street" => "address_1_street",
      "city" => "address_1_city",
      "state" => "address_1_state",
      "zip" => "address_1_zip",
      "postal_code" => "address_1_zip",
      "country" => "address_1_country"
    }.freeze

    def initialize(addressbook:, file:, filename:)
      @addressbook = addressbook
      @content = file.respond_to?(:read) ? file.read : file.to_s
      @content = @content.force_encoding("UTF-8")
      @filename = filename
    end

    def call
      vcards = parse_to_vcards
      imported = 0
      updated = 0
      failed = 0
      errors = []

      ActiveRecord::Base.transaction do
        @addressbook.increment_sync!
        token = @addressbook.sync_token

        vcards.each do |vcard_data|
          uid = extract_uid(vcard_data)

          existing = @addressbook.contacts.find_by(uid: uid) if uid.present?

          if existing
            existing.update!(vcard_data: vcard_data)
            @addressbook.sync_changes.create!(uri: existing.uri, sync_token: token, change_type: "modified")
            updated += 1
          else
            contact = @addressbook.contacts.new(uri: "#{SecureRandom.uuid}.vcf", vcard_data: vcard_data)
            contact.save!
            @addressbook.sync_changes.create!(uri: contact.uri, sync_token: token, change_type: "created")
            imported += 1
          end
        rescue => e
          failed += 1
          errors << e.message
        end
      end

      ImportResult.new(imported: imported, updated: updated, failed: failed, errors: errors)
    end

    private

    def parse_to_vcards
      ext = File.extname(@filename).downcase
      case ext
      when ".vcf" then parse_vcf
      when ".csv" then parse_csv
      when ".json" then parse_json
      else
        raise UnsupportedFormat, "Unsupported file format: #{ext}"
      end
    end

    def parse_vcf
      cards = @content.scan(/BEGIN:VCARD.*?END:VCARD/mi)
      raise ParseError, "No vCard entries found in file" if cards.empty?
      cards.map { |card| ensure_uid(card) }
    end

    def ensure_uid(vcard_data)
      return vcard_data if vcard_data.match?(/^UID(?:;[^:]*)?:/mi)
      vcard_data.sub(/^(END:VCARD)/mi, "UID:#{SecureRandom.uuid}\n\\1")
    end

    def parse_csv
      table = CSV.parse(@content.sub(/\A\xEF\xBB\xBF/, ""), headers: true)
      raise ParseError, "CSV file has no data rows" if table.empty?

      headers = normalize_headers(table.headers)

      table.filter_map do |row|
        data = {}
        headers.each_with_index do |header, i|
          data[header] = row[i]&.strip if header
        end

        full_name = data["full_name"]
        first_name = data["first_name"]
        last_name = data["last_name"]
        next if full_name.blank? && first_name.blank? && last_name.blank?

        emails = [ data["email_1"], data["email_2"], data["email_3"] ].compact_blank
        phones = [ data["phone_1"], data["phone_2"], data["phone_3"] ].compact_blank
        urls = [ data["url_1"], data["url_2"], data["url_3"] ].compact_blank

        addresses = []
        if data["address_1_street"].present? || data["address_1_city"].present?
          addresses << {
            type: "HOME",
            street: data["address_1_street"],
            city: data["address_1_city"],
            state: data["address_1_state"],
            zip: data["address_1_zip"],
            country: data["address_1_country"]
          }
        end

        params = {
          full_name: full_name,
          first_name: first_name,
          last_name: last_name,
          middle_name: data["middle_name"],
          name_prefix: data["name_prefix"],
          name_suffix: data["name_suffix"],
          nickname: data["nickname"],
          pronouns: data["pronouns"],
          emails: emails,
          phones: phones,
          organization: data["organization"],
          title: data["title"],
          role: data["role"],
          note: data["note"],
          birthday: data["birthday"],
          anniversary: data["anniversary"],
          urls: urls,
          addresses: addresses
        }
        params[:uid] = data["uid"] if data["uid"].present?
        if data["categories"].present?
          params[:categories] = data["categories"].split(",").map(&:strip)
        end

        Vcard::Parser.generate(params)
      end
    rescue CSV::MalformedCSVError => e
      raise ParseError, "Invalid CSV: #{e.message}"
    end

    def parse_json
      data = JSON.parse(@content)
      raise ParseError, "JSON must be an array of contacts" unless data.is_a?(Array)
      raise ParseError, "JSON file has no contacts" if data.empty?

      data.filter_map do |obj|
        obj = obj.transform_keys(&:to_s)
        full_name = obj["full_name"]
        first_name = obj["first_name"]
        last_name = obj["last_name"]
        next if full_name.blank? && first_name.blank? && last_name.blank?

        params = {
          full_name: full_name,
          first_name: first_name,
          last_name: last_name,
          middle_name: obj["middle_name"],
          name_prefix: obj["name_prefix"],
          name_suffix: obj["name_suffix"],
          nickname: obj["nickname"],
          pronouns: obj["pronouns"],
          gender: obj["gender"],
          emails: Array(obj["emails"]),
          phones: Array(obj["phones"]),
          impp: Array(obj["impp"]).map { |im| im.is_a?(Hash) ? im.transform_keys(&:to_sym) : nil }.compact,
          social_profiles: Array(obj["social_profiles"]).map { |sp| sp.is_a?(Hash) ? sp.transform_keys(&:to_sym) : nil }.compact,
          organization: obj["organization"],
          title: obj["title"],
          role: obj["role"],
          note: obj["note"],
          birthday: obj["birthday"],
          anniversary: obj["anniversary"],
          urls: Array(obj["urls"]),
          addresses: Array(obj["addresses"]).map { |a| a.is_a?(Hash) ? a.transform_keys(&:to_sym) : nil }.compact
        }
        params[:uid] = obj["uid"] if obj["uid"].present?
        if obj["categories"].present?
          params[:categories] = Array(obj["categories"])
        end

        Vcard::Parser.generate(params)
      end
    rescue JSON::ParserError => e
      raise ParseError, "Invalid JSON: #{e.message}"
    end

    def normalize_headers(headers)
      headers.map do |h|
        next nil if h.nil?
        normalized = h.strip.downcase.gsub(/\s+/, "_")
        HEADER_ALIASES[normalized] || normalized
      end
    end

    def extract_uid(vcard_data)
      if (match = vcard_data.match(/^UID(?:;[^:]*)?:(.+)$/i))
        match[1].strip
      end
    end
  end
end
