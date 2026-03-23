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
          uri = href.split("/").last
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
            href = "/dav/#{owner.username}/contacts/#{addressbook.uri}/#{contact.uri}"
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
            href = "/dav/#{owner.username}/contacts/#{addressbook.uri}/#{uri}"

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
          href = "/dav/#{owner.username}/contacts/#{addressbook.uri}/#{contact.uri}"
          ms.add_response(href: href) do |resp|
            resolve_props(resp, parsed[:props], :contact, contact, context)
          end
        end

        xml_response(207, ms.build)
      end

      def filter_contacts(addressbook, filter)
        contacts = addressbook.contacts.to_a

        filter[:prop_filters].each do |pf|
          next unless pf[:text_match]
          contacts = contacts.select do |c|
            prop_value = extract_vcard_prop(c.vcard_data, pf[:name])
            next false unless prop_value
            case pf[:match_type]
            when "contains"
              prop_value.downcase.include?(pf[:text_match].downcase)
            when "starts-with"
              prop_value.downcase.start_with?(pf[:text_match].downcase)
            when "ends-with"
              prop_value.downcase.end_with?(pf[:text_match].downcase)
            when "equals"
              prop_value.downcase == pf[:text_match].downcase
            else
              prop_value.downcase.include?(pf[:text_match].downcase)
            end
          end
        end

        contacts
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
