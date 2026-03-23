module CardDav
  module Properties
    class CalserverProperties
      NS = Xml::CALSERVER_NS

      def resolve(prop_name, resource_type, resource, _context)
        case prop_name
        when "getctag"
          resource_type == :addressbook ? { found: true, value: resource.ctag.to_s } : { found: false }
        else
          { found: false }
        end
      end
    end
  end
end
