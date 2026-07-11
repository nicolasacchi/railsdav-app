module CardDav
  module Xml
    class Parser
      def self.parse_propfind(xml_string)
        return { allprop: true, propname: false, props: [] } if xml_string.nil? || xml_string.strip.empty?

        doc = Nokogiri::XML(xml_string) { |config| config.nonet }
        doc.remove_namespaces!

        if doc.at_xpath("//allprop")
          { allprop: true, propname: false, props: [] }
        elsif doc.at_xpath("//propname")
          { allprop: false, propname: true, props: [] }
        else
          props = extract_props(Nokogiri::XML(xml_string) { |config| config.nonet })
          { allprop: false, propname: false, props: props }
        end
      end

      def self.parse_report(xml_string)
        return nil if xml_string.nil? || xml_string.strip.empty?

        doc = Nokogiri::XML(xml_string) { |config| config.nonet }
        ns = NAMESPACES

        root = doc.root
        return nil unless root

        report_type = detect_report_type(root, ns)
        props = extract_props(doc)

        case report_type
        when :multiget
          hrefs = doc.xpath("//d:href", ns).map(&:text)
          { type: :multiget, props: props, hrefs: hrefs }
        when :sync_collection
          token_el = doc.at_xpath("//d:sync-token", ns)
          sync_token = token_el&.text
          sync_token = nil if sync_token&.strip&.empty?
          { type: :sync_collection, props: props, sync_token: sync_token }
        when :query
          filter = parse_addressbook_filter(doc, ns)
          limit = parse_limit(doc, ns)
          { type: :query, props: props, filter: filter, limit: limit }
        else
          nil
        end
      end

      private

      def self.detect_report_type(root, ns)
        local = root.name.gsub(/.*:/, "")
        case local
        when "addressbook-multiget"
          :multiget
        when "sync-collection"
          :sync_collection
        when "addressbook-query"
          :query
        else
          nil
        end
      end

      def self.extract_props(doc)
        ns = NAMESPACES
        prop_el = doc.at_xpath("//d:prop", ns)
        return [] unless prop_el

        prop_el.children.select(&:element?).map do |child|
          { namespace: child.namespace&.href || DAV_NS, name: child.name }
        end
      end

      def self.parse_limit(doc, ns)
        limit_el = doc.at_xpath("//card:limit", ns)
        return nil unless limit_el

        nresults_el = limit_el.at_xpath("card:nresults", ns)
        return nil unless nresults_el

        value = nresults_el.text.strip.to_i
        value > 0 ? value : nil
      end

      def self.parse_addressbook_filter(doc, ns)
        filter_el = doc.at_xpath("//card:filter", ns)
        return nil unless filter_el

        prop_filters = filter_el.xpath("card:prop-filter", ns).map do |pf|
          name = pf["name"]
          is_not_defined = pf.at_xpath("card:is-not-defined", ns) ? true : false
          text_match_el = pf.at_xpath("card:text-match", ns)
          text_match = text_match_el&.text
          match_type = text_match_el&.[]("match-type") || "contains"
          { name: name, text_match: text_match, match_type: match_type, is_not_defined: is_not_defined }
        end

        test = filter_el["test"] || "anyof"
        { test: test, prop_filters: prop_filters }
      end
    end
  end
end
