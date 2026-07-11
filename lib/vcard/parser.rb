module Vcard
  class Parser
    ContactDisplay = Data.define(
      :full_name, :first_name, :last_name, :middle_name, :name_prefix, :name_suffix,
      :nickname, :pronouns, :gender,
      :emails, :phones, :impp, :social_profiles,
      :organization, :title, :role, :note,
      :photo_data, :photo_type,
      :addresses, :uid, :version,
      :urls, :birthday, :anniversary, :dates, :related,
      :categories, :kind, :member_uids,
      :phonetic_first_name, :phonetic_last_name,
      :geo, :logo, :sound, :rev, :prodid
    )

    def self.parse(vcard_string)
      return nil if vcard_string.nil? || vcard_string.strip.empty?

      vcard_string = vcard_string.scrub("")
      lines = unfold(vcard_string).lines.map(&:chomp)
      group_labels = extract_group_labels(lines)

      full_name = extract_value(lines, "FN")
      n_raw = extract_value(lines, "N", unescape: false)
      n_parts = n_raw ? split_structured(n_raw) : []
      last_name = n_parts[0]&.presence
      first_name = n_parts[1]&.presence
      middle_name = n_parts[2]&.presence
      name_prefix = n_parts[3]&.presence
      name_suffix = n_parts[4]&.presence

      emails = extract_typed_values(lines, "EMAIL", group_labels)
      phones = extract_typed_values(lines, "TEL", group_labels)

      if full_name.blank?
        full_name = [first_name, last_name].compact.join(" ").presence ||
                    emails.first&.dig(:value) ||
                    phones.first&.dig(:value) ||
                    extract_value(lines, "ORG")
      end

      organization = extract_value(lines, "ORG")
      title = extract_value(lines, "TITLE")
      role = extract_value(lines, "ROLE")
      note = extract_value(lines, "NOTE")
      uid = extract_value(lines, "UID")
      version = extract_value(lines, "VERSION")
      nickname = extract_value(lines, "NICKNAME")
      gender = extract_value(lines, "GENDER")
      pronouns = extract_value(lines, "PRONOUNS")
      geo = extract_value(lines, "GEO")
      rev = extract_value(lines, "REV")
      prodid = extract_value(lines, "PRODID")
      phonetic_first_name = extract_value(lines, "X-PHONETIC-FIRST-NAME")
      phonetic_last_name = extract_value(lines, "X-PHONETIC-LAST-NAME")

      logo_raw = extract_value(lines, "LOGO")
      logo = logo_raw&.match?(%r{\Ahttps?://}i) ? logo_raw : nil

      sound_raw = extract_value(lines, "SOUND")
      sound = sound_raw&.match?(%r{\Ahttps?://}i) ? sound_raw : nil

      photo_data, photo_type = extract_photo(lines)
      addresses = extract_typed_values(lines, "ADR", group_labels, unescape: false).map do |addr|
        parts = split_structured(addr[:value])
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
      impp = extract_typed_values(lines, "IMPP", group_labels)
      social_profiles = extract_typed_values(lines, "X-SOCIALPROFILE", group_labels)
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
        middle_name: middle_name,
        name_prefix: name_prefix,
        name_suffix: name_suffix,
        nickname: nickname,
        pronouns: pronouns,
        gender: gender,
        emails: emails,
        phones: phones,
        impp: impp,
        social_profiles: social_profiles,
        organization: organization,
        title: title,
        role: role,
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
        member_uids: member_uids,
        phonetic_first_name: phonetic_first_name,
        phonetic_last_name: phonetic_last_name,
        geo: geo,
        logo: logo,
        sound: sound,
        rev: rev,
        prodid: prodid
      )
    end

    def self.generate(params)
      uid = params[:uid] || SecureRandom.uuid
      kind = params[:kind]
      lines = ["BEGIN:VCARD", "VERSION:3.0", "UID:#{escape_text(uid)}"]

      if kind == "group"
        lines << "KIND:group"
        fn = params[:full_name].presence || "Unnamed Group"
        lines << "FN:#{escape_text(fn)}"
        lines << "N:#{escape_text(fn)};;;;"
        Array(params[:member_uids]).each do |member_uid|
          lines << "MEMBER:urn:uuid:#{member_uid}"
        end
      else
        fn = params[:full_name].presence
        first = params[:first_name].presence || ""
        last = params[:last_name].presence || ""
        middle = params[:middle_name].presence || ""
        prefix = params[:name_prefix].presence || ""
        suffix = params[:name_suffix].presence || ""
        fn ||= [prefix, first, middle, last, suffix].reject(&:empty?).join(" ")
        lines << "FN:#{escape_text(fn)}"
        lines << "N:#{[last, first, middle, prefix, suffix].map { |p| escape_text(p) }.join(';')}"

        lines << "NICKNAME:#{escape_text(params[:nickname])}" if params[:nickname].present?
        lines << "PRONOUNS:#{escape_text(params[:pronouns])}" if params[:pronouns].present?
        lines << "GENDER:#{escape_text(params[:gender])}" if params[:gender].present?

        Array(params[:emails]).each do |email|
          next if email.blank?
          lines << "EMAIL:#{escape_text(email)}"
        end

        Array(params[:phones]).each do |phone|
          next if phone.blank?
          lines << "TEL:#{escape_text(phone)}"
        end

        Array(params[:impp]).each do |im|
          next unless im.is_a?(Hash) || im.respond_to?(:to_h)
          im = im.to_h.symbolize_keys if im.respond_to?(:to_h)
          value = im[:value].presence
          next unless value
          type = im[:type].presence
          lines << (type ? "IMPP;TYPE=#{escape_param(type)}:#{escape_text(value)}" : "IMPP:#{escape_text(value)}")
        end

        lines << "ORG:#{escape_text(params[:organization])}" if params[:organization].present?
        lines << "TITLE:#{escape_text(params[:title])}" if params[:title].present?
        lines << "ROLE:#{escape_text(params[:role])}" if params[:role].present?
        lines << "NOTE:#{escape_text(params[:note])}" if params[:note].present?

        lines << "BDAY:#{escape_text(params[:birthday])}" if params[:birthday].present?
        lines << "ANNIVERSARY:#{escape_text(params[:anniversary])}" if params[:anniversary].present?

        Array(params[:urls]).each do |url|
          next if url.blank?
          lines << "URL:#{escape_text(url)}"
        end

        Array(params[:addresses]).each do |addr|
          next unless addr.is_a?(Hash) || addr.respond_to?(:to_h)
          addr = addr.to_h.symbolize_keys if addr.respond_to?(:to_h)
          street = addr[:street].presence || ""
          city = addr[:city].presence || ""
          state = addr[:state].presence || ""
          zip = addr[:zip].presence || ""
          country = addr[:country].presence || ""
          next if [street, city, state, zip, country].all?(&:blank?)
          type = addr[:type].presence || "HOME"
          parts = [street, city, state, zip, country].map { |p| escape_text(p) }
          lines << "ADR;TYPE=#{escape_param(type)}:;;#{parts.join(';')}"
        end

        Array(params[:social_profiles]).each do |sp|
          next unless sp.is_a?(Hash) || sp.respond_to?(:to_h)
          sp = sp.to_h.symbolize_keys if sp.respond_to?(:to_h)
          value = sp[:value].presence
          next unless value
          type = sp[:type].presence
          lines << (type ? "X-SOCIALPROFILE;TYPE=#{escape_param(type)}:#{escape_text(value)}" : "X-SOCIALPROFILE:#{escape_text(value)}")
        end

        if params[:photo_url].present?
          lines << "PHOTO;VALUE=uri:#{escape_text(params[:photo_url])}"
        end

        categories = Array(params[:categories]).reject(&:blank?)
        if categories.any?
          lines << "CATEGORIES:#{categories.map { |c| escape_text(c) }.join(",")}"
        end
      end

      lines << "END:VCARD"
      lines.join("\r\n") + "\r\n"
    end

    # Escape a vCard TEXT value per RFC 6350 §3.4: backslash, comma and semicolon
    # are escaped, and CR/LF become a literal "\n". Critically this neutralizes
    # embedded newlines so user input can't inject additional vCard lines or
    # properties. Single-pass block form avoids double-escaping and gsub
    # replacement-string backreference pitfalls.
    def self.escape_text(value)
      value.to_s.gsub(/[\\;,]|\r\n|\r|\n/) do |m|
        case m
        when "\\" then "\\\\"
        when ";"  then "\\;"
        when ","  then "\\,"
        else "\\n"
        end
      end
    end

    # Escape a structured-value / parameter token: strip characters that would
    # break out of the TYPE=... parameter or the property name (CR/LF, ; : ,).
    def self.escape_param(value)
      value.to_s.gsub(/[\r\n;:,]/, " ").strip
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

    def self.extract_value(lines, property, unescape: true)
      re = PROP_RE.call(property)
      lines.each do |line|
        if line.match?(re)
          value = line.sub(re, "").strip
          value = decode_qp(value) if line.match?(/ENCODING=QUOTED-PRINTABLE/i)
          value = value.scrub("") unless value.valid_encoding?
          value = unescape_text(value) if unescape
          return value
        end
      end
      nil
    end

    def self.extract_typed_values(lines, property, group_labels = {}, unescape: true)
      re = PROP_RE.call(property)
      results = []
      lines.each do |line|
        next unless (m = line.match(re))
        group = m[1]&.downcase
        value = line.sub(re, "").strip
        value = decode_qp(value) if line.match?(/ENCODING=QUOTED-PRINTABLE/i)
        value = value.scrub("") unless value.valid_encoding?
        value = unescape_text(value) if unescape
        type = resolve_type(line, group, group_labels)
        results << { type: type, value: value }
      end
      results
    end

    # Reverse of escape_text: interpret RFC 6350 escapes. Recognized escapes are
    # \n / \N (newline), \\ (backslash), \, and \; ; an unrecognized \x yields x.
    def self.unescape_text(value)
      value.to_s.gsub(/\\(.)/) do
        case $1
        when "n", "N" then "\n"
        else $1
        end
      end
    end

    # Split a structured value (N, ADR) on unescaped semicolons, then unescape
    # each component so escaped \; survives as a literal within a component.
    def self.split_structured(value)
      value.split(/(?<!\\);/, -1).map { |part| unescape_text(part) }
    end

    def self.resolve_type(line, group, group_labels)
      if (tm = line.match(/TYPE=([^;:,]+)/i))
        type = tm[1]
        type = type.sub(/\AX-/i, "") if type.match?(/\AX-.+/i)
        return type
      end
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
        cats = value.split(/(?<!\\),/).map { |c| unescape_text(c).strip }
        all_categories.concat(cats)
      end
      all_categories.reject(&:blank?).uniq
    end

    def self.extract_kind(lines)
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
