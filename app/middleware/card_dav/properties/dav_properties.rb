module CardDav
  module Properties
    class DavProperties
      NS = Xml::DAV_NS

      def resolve(prop_name, resource_type, resource, context)
        case prop_name
        when "resourcetype"
          resolve_resourcetype(resource_type)
        when "displayname"
          resolve_displayname(resource_type, resource, context)
        when "current-user-principal"
          if context.user
            { found: true, value: nil, block: ->(xml) { xml["d"].href("/dav/#{context.user.username}/") } }
          else
            { found: true, value: nil, block: ->(xml) { xml["d"].unauthenticated } }
          end
        when "getetag"
          resource_type == :contact ? { found: true, value: resource.etag } : { found: false }
        when "getcontenttype"
          if resource_type == :contact
            ct = resource.encrypted? ? "application/octet-stream" : "text/vcard; charset=utf-8"
            { found: true, value: ct }
          else
            { found: false }
          end
        when "getcontentlength"
          resource_type == :contact ? { found: true, value: resource.vcard_data.bytesize.to_s } : { found: false }
        when "getlastmodified"
          if resource.respond_to?(:updated_at) && resource.updated_at
            { found: true, value: resource.updated_at.httpdate }
          else
            { found: false }
          end
        when "creationdate"
          if resource.respond_to?(:created_at) && resource.created_at
            { found: true, value: resource.created_at.iso8601 }
          else
            { found: false }
          end
        when "owner"
          owner_name = context.username_from_path || context.user&.username
          owner_name ? { found: true, value: nil, block: ->(xml) { xml["d"].href("/dav/#{owner_name}/") } } : { found: false }
        when "current-user-privilege-set"
          if context.share && !context.share.writable?
            { found: true, value: nil, block: ->(xml) {
              xml["d"].privilege { xml["d"].read }
            } }
          elsif context.public_token
            { found: true, value: nil, block: ->(xml) {
              xml["d"].privilege { xml["d"].read }
            } }
          else
            { found: true, value: nil, block: ->(xml) {
              xml["d"].privilege { xml["d"].read }
              xml["d"].privilege { xml["d"].write }
              xml["d"].privilege { xml["d"].send("write-content") }
              xml["d"].privilege { xml["d"].send("bind") }
              xml["d"].privilege { xml["d"].send("unbind") }
              xml["d"].privilege { xml["d"].all }
            } }
          end
        when "supported-report-set"
          resolve_supported_reports(resource_type)
        when "sync-token"
          resource_type == :addressbook ? { found: true, value: resource.sync_token_url } : { found: false }
        else
          { found: false }
        end
      end

      private

      def resolve_resourcetype(resource_type)
        case resource_type
        when :dav_root, :principal, :home_set
          { found: true, value: nil, block: ->(xml) { xml["d"].collection } }
        when :addressbook
          { found: true, value: nil, block: ->(xml) {
            xml["d"].collection
            xml["card"].addressbook
          } }
        when :contact
          { found: true, value: nil, block: ->(_xml) {} }
        else
          { found: false }
        end
      end

      def resolve_displayname(resource_type, resource, context)
        case resource_type
        when :dav_root
          { found: true, value: "CardDAV" }
        when :principal
          { found: true, value: context.user.username }
        when :home_set
          { found: true, value: "Address Books" }
        when :addressbook
          { found: true, value: resource.displayname }
        when :contact
          { found: true, value: resource.uri }
        else
          { found: false }
        end
      end

      def resolve_supported_reports(resource_type)
        return { found: false } unless resource_type == :addressbook

        { found: true, value: nil, block: ->(xml) {
          xml["d"].send("supported-report") { xml["d"].report { xml["card"].send("addressbook-multiget") } }
          xml["d"].send("supported-report") { xml["d"].report { xml["card"].send("addressbook-query") } }
          xml["d"].send("supported-report") { xml["d"].report { xml["d"].send("sync-collection") } }
        } }
      end
    end
  end
end
