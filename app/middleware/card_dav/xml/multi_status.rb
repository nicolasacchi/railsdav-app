module CardDav
  module Xml
    class MultiStatus
      def initialize
        @responses = []
        @sync_token = nil
      end

      def set_sync_token(token)
        @sync_token = token
      end

      def add_response(href:, status: nil, &block)
        resp = Response.new(href, status)
        yield(resp) if block_given?
        @responses << resp
      end

      def build
        builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
          xml["d"].multistatus(
            "xmlns:d" => DAV_NS,
            "xmlns:card" => CARDDAV_NS,
            "xmlns:cs" => CALSERVER_NS
          ) do
            @responses.each { |r| r.build(xml) }
            if @sync_token
              xml["d"].send("sync-token", @sync_token)
            end
          end
        end
        builder.to_xml
      end

      class Response
        def initialize(href, status = nil)
          @href = href
          @status = status
          @found_props = []
          @not_found_props = []
        end

        def prop(namespace, name, value = nil, &block)
          @found_props << { namespace: namespace, name: name, value: value, block: block }
        end

        def prop_not_found(namespace, name)
          @not_found_props << { namespace: namespace, name: name }
        end

        def build(xml)
          xml["d"].response do
            xml["d"].href(@href)

            if @status && @found_props.empty? && @not_found_props.empty?
              xml["d"].status("HTTP/1.1 #{@status}")
            else
              unless @found_props.empty?
                xml["d"].propstat do
                  xml["d"].prop do
                    @found_props.each { |p| render_prop(xml, p) }
                  end
                  xml["d"].status("HTTP/1.1 200 OK")
                end
              end

              unless @not_found_props.empty?
                xml["d"].propstat do
                  xml["d"].prop do
                    @not_found_props.each { |p| render_prop_empty(xml, p) }
                  end
                  xml["d"].status("HTTP/1.1 404 Not Found")
                end
              end
            end
          end
        end

        private

        def render_prop(xml, prop)
          prefix = prefix_for(prop[:namespace])
          if prop[:block]
            xml[prefix].send(prop[:name]) do
              prop[:block].call(xml)
            end
          elsif prop[:value]
            xml[prefix].send(prop[:name], prop[:value])
          else
            xml[prefix].send(prop[:name])
          end
        end

        def render_prop_empty(xml, prop)
          prefix = prefix_for(prop[:namespace])
          xml[prefix].send(prop[:name])
        end

        def prefix_for(namespace)
          NAMESPACES.key(namespace) || "d"
        end
      end
    end
  end
end
