module Vcard
  class Parser
    ContactDisplay = Data.define(
      :full_name, :first_name, :last_name, :emails, :phones,
      :organization, :title, :note, :photo_data, :photo_type,
      :addresses, :uid, :version,
      :urls, :birthday, :anniversary, :dates, :related,
      :categories, :kind, :member_uids
    )

    def self.parse(vcard_string)
      return nil if vcard_string.nil? || vcard_string.strip.empty?

      vcard_string = vcard_string.scrub("")
      lines = unfold(vcard_string).lines.map(&:chomp)
      group_labels = extract_group_labels(lines)

      full_name = extract_value(lines, "FN")
      n_parts = extract_value(lines, "N")&.split(";") || []
      last_name = n_parts[0]&.presence
      first_name = n_parts[1]&.presence
      emails = extract_typed_values(lines, "EMAIL", group_labels)
      phones = extract_typed_values(lines, "TEL", group_labels)

      # Fallback display name when FN is missing
      if full_name.blank?
        full_name = [first_name, last_name].compact.join(" ").presence ||
                    emails.first&.dig(:value) ||
                    phones.first&.dig(:value) ||
                    extract_value(lines, "ORG")
      end
      organization = extract_value(lines, "ORG")
      title = extract_value(lines, "TITLE")
      note = extract_value(lines, "NOTE")
      uid = extract_value(lines, "UID")
      version = extract_value(lines, "VERSION")
      photo_data, photo_type = extract_photo(lines)
      addresses = extract_typed_values(lines, "ADR", group_labels).map do |addr|
        parts = addr[:value].split(";")
        {
          type: addr[:type],
          street: parts[2],
          city: parts[3],
          state: parts[4],
          zip: parts[5],
          country: parts[6]
        }.compact
      end
      urls = extract_typed_values(lines, "URL", group_labels)
      birthday = extract_value(lines, "BDAY")
      anniversary = extract_value(lines, "ANNIVERSARY")
      dates = extract_typed_values(lines, "X-ABDATE", group_labels)
      related = extract_typed_values(lines, "RELATED", group_labels)
      categories = extract_categories(lines)
      kind = extract_kind(lines)
      member_uids = extract_member_uids(lines)

      ContactDisplay.new(
        full_name: full_name,
        first_name: first_name,
        last_name: last_name,
        emails: emails,
        phones: phones,
        organization: organization,
        title: title,
        note: note,
        photo_data: photo_data,
        photo_type: photo_type,
        addresses: addresses,
        uid: uid,
        version: version,
        urls: urls,
        birthday: birthday,
        anniversary: anniversary,
        dates: dates,
        related: related,
        categories: categories,
        kind: kind,
        member_uids: member_uids
      )
    end

    def self.generate(params)
      uid = params[:uid] || SecureRandom.uuid
      kind = params[:kind]
      lines = ["BEGIN:VCARD", "VERSION:3.0", "UID:#{uid}"]

      if kind == "group"
        lines << "KIND:group"
        fn = params[:full_name].presence || "Unnamed Group"
        lines << "FN:#{fn}"
        lines << "N:#{fn};;;;"
        Array(params[:member_uids]).each do |member_uid|
          lines << "MEMBER:urn:uuid:#{member_uid}"
        end
      else
        fn = params[:full_name].presence
        first = params[:first_name].presence || ""
        last = params[:last_name].presence || ""
        fn ||= [first, last].reject(&:empty?).join(" ")
        lines << "FN:#{fn}"
        lines << "N:#{last};#{first};;;"

        Array(params[:emails]).each do |email|
          next if email.blank?
          lines << "EMAIL:#{email}"
        end

        Array(params[:phones]).each do |phone|
          next if phone.blank?
          lines << "TEL:#{phone}"
        end

        lines << "ORG:#{params[:organization]}" if params[:organization].present?
        lines << "TITLE:#{params[:title]}" if params[:title].present?
        lines << "NOTE:#{params[:note]}" if params[:note].present?

        categories = Array(params[:categories]).reject(&:blank?)
        if categories.any?
          escaped = categories.map { |c| c.gsub(",", "\\,") }
          lines << "CATEGORIES:#{escaped.join(",")}"
        end
      end

      lines << "END:VCARD"
      lines.join("\r\n") + "\r\n"
    end

    def self.update_categories(vcard_data, categories)
      lines = vcard_data.lines.map(&:chomp)
      lines.reject! { |l| l.match?(/^(?:item\d+\.)?CATEGORIES(?:;[^:]*)?:/i) }

      if categories.any?
        escaped = categories.map { |c| c.gsub(",", "\\,") }
        cat_line = "CATEGORIES:#{escaped.join(",")}"
        end_idx = lines.rindex { |l| l.match?(/^END:VCARD/i) }
        lines.insert(end_idx, cat_line) if end_idx
      end

      lines.join("\r\n") + "\r\n"
    end

    def self.update_members(vcard_data, uids)
      lines = vcard_data.lines.map(&:chomp)
      lines.reject! { |l| l.match?(/^(?:item\d+\.)?(?:X-ADDRESSBOOKSERVER-)?MEMBER(?:;[^:]*)?:/i) }

      if uids.any?
        end_idx = lines.rindex { |l| l.match?(/^END:VCARD/i) }
        if end_idx
          uids.each_with_index do |uid, i|
            lines.insert(end_idx + i, "MEMBER:urn:uuid:#{uid}")
          end
        end
      end

      lines.join("\r\n") + "\r\n"
    end

    private

    PROP_RE = ->(prop) { /^(?:(item\d+)\.)?#{Regexp.escape(prop)}(?:;[^:]*)?:/i }

    def self.unfold(text)
      text.gsub(/=\r?\n/, "").gsub(/\r?\n[ \t]/, "")
    end

    def self.decode_qp(value)
      value.gsub(/=([0-9A-Fa-f]{2})/) { [$1].pack("H2") }.force_encoding("UTF-8")
    end

    def self.extract_group_labels(lines)
      labels = {}
      lines.each do |line|
        if (m = line.match(/^(item\d+)\.X-ABLABEL:(.*)/i))
          labels[m[1].downcase] = m[2].strip
        end
      end
      labels
    end

    def self.extract_value(lines, property)
      re = PROP_RE.call(property)
      lines.each do |line|
        if line.match?(re)
          value = line.sub(re, "").strip
          value = decode_qp(value) if line.match?(/ENCODING=QUOTED-PRINTABLE/i)
          value = value.scrub("") unless value.valid_encoding?
          return value
        end
      end
      nil
    end

    def self.extract_typed_values(lines, property, group_labels = {})
      re = PROP_RE.call(property)
      results = []
      lines.each do |line|
        next unless (m = line.match(re))
        group = m[1]&.downcase
        value = line.sub(re, "").strip
        value = decode_qp(value) if line.match?(/ENCODING=QUOTED-PRINTABLE/i)
        value = value.scrub("") unless value.valid_encoding?
        type = resolve_type(line, group, group_labels)
        results << { type: type, value: value }
      end
      results
    end

    def self.resolve_type(line, group, group_labels)
      # Try TYPE= param first
      if (tm = line.match(/TYPE=([^;:,]+)/i))
        type = tm[1]
        # vCard 2.1 custom types: X-Gggg → Gggg
        type = type.sub(/\AX-/i, "") if type.match?(/\AX-.+/i)
        return type
      end
      # Try group label (item1.X-ABLABEL)
      return group_labels[group] if group && group_labels[group]
      nil
    end

    def self.extract_photo(lines)
      re = PROP_RE.call("PHOTO")
      photo_line = lines.find { |l| l.match?(re) }
      return [nil, nil] unless photo_line

      type_match = photo_line.match(/TYPE=([^;:,]+)/i)
      photo_type = type_match ? type_match[1].downcase : "jpeg"
      data = photo_line.sub(re, "").strip
      [data, photo_type]
    end

    def self.extract_categories(lines)
      re = PROP_RE.call("CATEGORIES")
      all_categories = []
      lines.each do |line|
        next unless line.match?(re)
        value = line.sub(re, "").strip
        # Split on unescaped commas (commas not preceded by backslash)
        cats = value.split(/(?<!\\),/).map { |c| c.gsub("\\,", ",").strip }
        all_categories.concat(cats)
      end
      all_categories.reject(&:blank?).uniq
    end

    def self.extract_kind(lines)
      # Check KIND property first, then Apple's X-ADDRESSBOOKSERVER-KIND
      re_kind = PROP_RE.call("KIND")
      re_apple = PROP_RE.call("X-ADDRESSBOOKSERVER-KIND")
      lines.each do |line|
        if line.match?(re_kind)
          return line.sub(re_kind, "").strip.downcase
        end
        if line.match?(re_apple)
          return line.sub(re_apple, "").strip.downcase
        end
      end
      "individual"
    end

    def self.extract_member_uids(lines)
      re_member = PROP_RE.call("MEMBER")
      re_apple = PROP_RE.call("X-ADDRESSBOOKSERVER-MEMBER")
      uids = []
      lines.each do |line|
        if line.match?(re_member)
          value = line.sub(re_member, "").strip
          if (m = value.match(/urn:uuid:(.+)/i))
            uids << m[1].strip
          end
        elsif line.match?(re_apple)
          value = line.sub(re_apple, "").strip
          if (m = value.match(/urn:uuid:(.+)/i))
            uids << m[1].strip
          end
        end
      end
      uids
    end
  end
end
