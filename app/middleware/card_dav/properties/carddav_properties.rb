module CardDav
  module Properties
    class CarddavProperties
      NS = Xml::CARDDAV_NS

      def resolve(prop_name, resource_type, resource, context)
        case prop_name
        when "addressbook-home-set"
          if [:principal, :dav_root].include?(resource_type)
            { found: true, value: nil, block: ->(xml) {
              xml["d"].href("/dav/#{context.user.username}/contacts/")
            } }
          else
            { found: false }
          end
        when "supported-address-data"
          if resource_type == :addressbook
            { found: true, value: nil, block: ->(xml) {
              xml["card"].send("address-data-type", "content-type" => "text/vcard", "version" => "3.0")
              xml["card"].send("address-data-type", "content-type" => "text/vcard", "version" => "4.0")
            } }
          else
            { found: false }
          end
        when "max-resource-size"
          resource_type == :addressbook ? { found: true, value: "1048576" } : { found: false }
        when "addressbook-description"
          resource_type == :addressbook ? { found: true, value: resource.description || "" } : { found: false }
        when "address-data"
          resource_type == :contact ? { found: true, value: resource.vcard_data } : { found: false }
        else
          { found: false }
        end
      end
    end
  end
end
