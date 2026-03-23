module CardDav
  class RequestContext
    attr_reader :env, :method, :path, :depth, :body, :content_type,
                :if_match, :if_none_match
    attr_accessor :user, :share, :shared_addressbook, :public_token
    attr_writer :path_segments, :resource_type

    def initialize(env)
      @env = env
      @method = env["REQUEST_METHOD"].upcase
      @path = normalize_path(env["PATH_INFO"] || "/")
      @depth = parse_depth(env["HTTP_DEPTH"])
      @content_type = env["CONTENT_TYPE"]
      @if_match = parse_etag_header(env["HTTP_IF_MATCH"])
      @if_none_match = parse_etag_header(env["HTTP_IF_NONE_MATCH"])
      @body = read_body(env)
    end

    def path_segments
      @path_segments ||= begin
        segments = path.sub(%r{^/dav/?}, "").split("/").reject(&:empty?)
        segments
      end
    end

    def resource_type
      @resource_type ||= case path_segments.length
      when 0
        :dav_root
      when 1
        :principal
      when 2
        path_segments[1] == "contacts" ? :home_set : :unknown
      when 3
        :addressbook
      when 4
        :contact
      else
        :unknown
      end
    end

    def username_from_path
      path_segments[0]
    end

    def addressbook_uri
      path_segments[2]
    end

    def contact_uri
      path_segments[3]
    end

    private

    def normalize_path(path)
      path = path.chomp("/") + "/" unless path.end_with?(".vcf")
      path
    end

    def parse_depth(header)
      case header
      when "0" then "0"
      when "1" then "1"
      when "infinity" then "infinity"
      when nil then "0"
      else "0"
      end
    end

    def parse_etag_header(header)
      return nil if header.nil?
      return ["*"] if header.strip == "*"
      header.scan(/"[^"]*"/)
    end

    def read_body(env)
      input = env["rack.input"]
      return nil unless input
      input.rewind
      data = input.read
      input.rewind
      return nil if data.empty?
      data.force_encoding("UTF-8") if data.encoding == Encoding::ASCII_8BIT
      data
    end
  end
end
