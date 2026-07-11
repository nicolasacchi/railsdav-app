module CardDav
  module Handlers
    class PropfindHandler
      include ResponseHelper

      ALLPROPS = [
        { namespace: Xml::DAV_NS, name: "resourcetype" },
        { namespace: Xml::DAV_NS, name: "displayname" },
        { namespace: Xml::DAV_NS, name: "getcontenttype" },
        { namespace: Xml::DAV_NS, name: "getcontentlength" },
        { namespace: Xml::DAV_NS, name: "getetag" },
        { namespace: Xml::DAV_NS, name: "getlastmodified" },
        { namespace: Xml::DAV_NS, name: "creationdate" },
        { namespace: Xml::DAV_NS, name: "current-user-principal" },
        { namespace: Xml::DAV_NS, name: "owner" },
        { namespace: Xml::DAV_NS, name: "supported-report-set" },
        { namespace: Xml::DAV_NS, name: "sync-token" },
        { namespace: Xml::DAV_NS, name: "current-user-privilege-set" },
        { namespace: Xml::CARDDAV_NS, name: "addressbook-home-set" },
        { namespace: Xml::CARDDAV_NS, name: "supported-address-data" },
        { namespace: Xml::CARDDAV_NS, name: "max-resource-size" },
        { namespace: Xml::CARDDAV_NS, name: "addressbook-description" },
        { namespace: Xml::CALSERVER_NS, name: "getctag" },
      ].freeze

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

        if context.depth == "infinity"
          return forbidden("Depth: infinity not allowed")
        end

        parsed = Xml::Parser.parse_propfind(context.body)
        requested_props = parsed[:allprop] ? ALLPROPS : parsed[:props]

        resource = load_resource(context)
        return not_found unless resource

        ms = Xml::MultiStatus.new
        add_resource_response(ms, context, resource, context.resource_type, requested_props)

        if context.depth == "1"
          add_children_responses(ms, context, resource, requested_props)
        end

        xml_response(207, ms.build)
      end

      private

      def load_resource(context)
        case context.resource_type
        when :dav_root
          context.user
        when :principal
          context.user
        when :home_set
          context.user
        when :addressbook
          find_addressbook(context)
        when :contact
          ab = find_addressbook(context)
          ab ? find_contact(ab, context) : nil
        else
          nil
        end
      end

      def add_resource_response(ms, context, resource, resource_type, props)
        href = href_for(context, resource_type, resource)
        ms.add_response(href: href) do |resp|
          resolve_props(resp, props, resource_type, resource, context)
        end
      end

      def add_children_responses(ms, context, resource, props)
        case context.resource_type
        when :dav_root, :principal
          # No children to list at principal level for PROPFIND depth 1
          # (addressbook-home-set is returned as a property, not as children)
        when :home_set
          context.user.addressbooks.each do |ab|
            href = "/dav/#{context.user.username}/contacts/#{ab.uri}/"
            ms.add_response(href: href) do |resp|
              resolve_props(resp, props, :addressbook, ab, context)
            end
          end
          # Include addressbooks shared with this user
          if context.user
            AddressbookShare.for_user(context.user).includes(addressbook: :user).each do |share|
              ab = share.addressbook
              owner = ab.user
              href = "/dav/#{owner.username}/contacts/#{ab.uri}/"
              ms.add_response(href: href) do |resp|
                saved_share = context.share
                context.share = share
                resolve_props(resp, props, :addressbook, ab, context)
                context.share = saved_share
              end
            end
          end
        when :addressbook
          addressbook = resource
          owner = addressbook.user
          addressbook.contacts.each do |contact|
            href = "/dav/#{owner.username}/contacts/#{addressbook.uri}/#{encode_uri_segment(contact.uri)}"
            ms.add_response(href: href) do |resp|
              resolve_props(resp, props, :contact, contact, context)
            end
          end
        end
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

      def href_for(context, resource_type, resource)
        case resource_type
        when :dav_root
          "/dav/"
        when :principal
          "/dav/#{context.username_from_path}/"
        when :home_set
          "/dav/#{context.username_from_path}/contacts/"
        when :addressbook
          owner = resource.user
          "/dav/#{owner.username}/contacts/#{resource.uri}/"
        when :contact
          owner = resource.addressbook.user
          "/dav/#{owner.username}/contacts/#{resource.addressbook.uri}/#{encode_uri_segment(resource.uri)}"
        end
      end
    end
  end
end
