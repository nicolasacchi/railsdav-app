module CardDav
  module Handlers
    class ReportHandler
      include ResponseHelper

      def initialize
        @resolvers = [
          Properties::DavProperties.new,
          Properties::CarddavProperties.new,
          Properties::CalserverProperties.new
        ]
      end

      def call(context)
        auth_error = authorize!(context)
        return auth_error if auth_error

        return bad_request("Request body required") unless context.body

        parsed = Xml::Parser.parse_report(context.body)
        return bad_request("Invalid report") unless parsed

        addressbook = find_addressbook(context)
        return not_found unless addressbook

        case parsed[:type]
        when :multiget
          handle_multiget(context, addressbook, parsed)
        when :sync_collection
          handle_sync_collection(context, addressbook, parsed)
        when :query
          handle_query(context, addressbook, parsed)
        else
          bad_request("Unknown report type")
        end
      end

      private

      def handle_multiget(context, addressbook, parsed)
        ms = Xml::MultiStatus.new

        parsed[:hrefs].each do |href|
          uri = decode_uri_segment(href.split("/").last)
          contact = addressbook.contacts.find_by(uri: uri)

          if contact
            ms.add_response(href: href) do |resp|
              resolve_props(resp, parsed[:props], :contact, contact, context)
            end
          else
            ms.add_response(href: href, status: "404 Not Found")
          end
        end

        xml_response(207, ms.build)
      end

      def handle_sync_collection(context, addressbook, parsed)
        ms = Xml::MultiStatus.new
        owner = addressbook.user

        if parsed[:sync_token].nil? || parsed[:sync_token].strip.empty?
          # Initial sync: return all contacts
          addressbook.contacts.each do |contact|
            href = "/dav/#{owner.username}/contacts/#{addressbook.uri}/#{encode_uri_segment(contact.uri)}"
            ms.add_response(href: href) do |resp|
              resolve_props(resp, parsed[:props], :contact, contact, context)
            end
          end
        else
          token_value = Addressbook.parse_sync_token(parsed[:sync_token])

          if token_value.nil? || token_value > addressbook.sync_token
            return xml_response(403, error_xml("valid-sync-token"))
          end

          changes = addressbook.sync_changes.since_token(token_value).order(:sync_token)

          # Group by URI, keep latest change per URI
          latest_changes = {}
          changes.each { |c| latest_changes[c.uri] = c }

          latest_changes.each do |uri, change|
            href = "/dav/#{owner.username}/contacts/#{addressbook.uri}/#{encode_uri_segment(uri)}"

            if change.change_type == "deleted"
              ms.add_response(href: href, status: "404 Not Found")
            else
              contact = addressbook.contacts.find_by(uri: uri)
              if contact
                ms.add_response(href: href) do |resp|
                  resolve_props(resp, parsed[:props], :contact, contact, context)
                end
              else
                ms.add_response(href: href, status: "404 Not Found")
              end
            end
          end
        end

        ms.set_sync_token(addressbook.sync_token_url)
        xml_response(207, ms.build)
      end

      def handle_query(context, addressbook, parsed)
        ms = Xml::MultiStatus.new
        owner = addressbook.user

        contacts = if parsed[:filter] && parsed[:filter][:prop_filters]&.any?
          result = filter_contacts(addressbook, parsed[:filter])
          parsed[:limit] ? result.first(parsed[:limit]) : result
        else
          scope = addressbook.contacts
          scope = scope.limit(parsed[:limit]) if parsed[:limit]
          scope.to_a
        end

        contacts.each do |contact|
          href = "/dav/#{owner.username}/contacts/#{addressbook.uri}/#{encode_uri_segment(contact.uri)}"
          ms.add_response(href: href) do |resp|
            resolve_props(resp, parsed[:props], :contact, contact, context)
          end
        end

        xml_response(207, ms.build)
      end

      def filter_contacts(addressbook, filter)
        # Encrypted contacts cannot be searched by content
        contacts = addressbook.contacts.where(encrypted: false).to_a
        prop_filters = filter[:prop_filters]
        return contacts if prop_filters.blank?

        # RFC 6352 §10.5.1: filter/@test is "anyof" (logical OR, the default) or
        # "allof" (logical AND). Previously every prop-filter was AND'd regardless.
        if filter[:test].to_s.downcase == "allof"
          contacts.select { |c| prop_filters.all? { |pf| prop_filter_matches?(c, pf) } }
        else
          contacts.select { |c| prop_filters.any? { |pf| prop_filter_matches?(c, pf) } }
        end
      end

      def prop_filter_matches?(contact, pf)
        if pf[:is_not_defined]
          extract_vcard_prop(contact.vcard_data, pf[:name]).nil?
        elsif pf[:text_match]
          prop_value = extract_vcard_prop(contact.vcard_data, pf[:name])
          return false unless prop_value
          needle = pf[:text_match].downcase
          haystack = prop_value.downcase
          case pf[:match_type]
          when "starts-with" then haystack.start_with?(needle)
          when "ends-with"   then haystack.end_with?(needle)
          when "equals"      then haystack == needle
          else                    haystack.include?(needle)
          end
        else
          # prop-filter without text-match or is-not-defined = property must exist
          !extract_vcard_prop(contact.vcard_data, pf[:name]).nil?
        end
      end

      def extract_vcard_prop(vcard_data, prop_name)
        pattern = /\A#{Regexp.escape(prop_name)}(?:;[^:]*)?:(.+)/i
        vcard_data.each_line do |line|
          match = line.strip.match(pattern)
          return match[1].strip if match
        end
        nil
      end

      def resolve_props(resp, props, resource_type, resource, context)
        props.each do |prop|
          resolved = nil
          @resolvers.each do |resolver|
            result = resolver.resolve(prop[:name], resource_type, resource, context)
            if result[:found]
              resolved = result
              break
            end
          end

          if resolved
            if resolved[:block]
              resp.prop(prop[:namespace], prop[:name], nil, &resolved[:block])
            else
              resp.prop(prop[:namespace], prop[:name], resolved[:value])
            end
          else
            resp.prop_not_found(prop[:namespace], prop[:name])
          end
        end
      end

      def error_xml(error_type)
        builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
          xml["d"].error("xmlns:d" => Xml::DAV_NS) do
            xml["d"].send(error_type)
          end
        end
        builder.to_xml
      end
    end
  end
end
