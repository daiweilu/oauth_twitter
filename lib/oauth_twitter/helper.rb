require "securerandom"
require "openssl"
require "base64"
require "uri"
require "net/http"
require "multi_json"

module OauthTwitter
  module Helper

    ##
    # Generate oauth params
    def oauth_params(include_oauth_token=true, addional_oauth_params={})
      oauth = {
        :oauth_consumer_key     => Config.consumer_key,
        :oauth_nonce            => SecureRandom.hex(21),
        :oauth_signature_method => "HMAC-SHA1",
        :oauth_timestamp        => Time.now.to_i,
        :oauth_version          => "1.0"
      }
      oauth[:oauth_token] = self.oauth_token if include_oauth_token == true
      return oauth.merge(addional_oauth_params)
    end

    ##
    # percent_encode disallowed char
    RESERVED_CHARS = /[^a-zA-Z0-9\-\.\_\~]/

    ##
    # percent_encode strigns
    def self.percent_encode(raw)
      return URI.escape(raw.to_s, RESERVED_CHARS)
    end

    ##
    # Twitter API root url
    HOST = "https://api.twitter.com"

    ##
    # Helper method to send request to Twitter API
    # @param method [Symbol] HTTP method, support :GET or :POST
    # @param path [String] request url path
    # @param query [Hash] request parameters
    # @param oauth [Hash] oauth request header
    #
    # @return [Array] 0: indicate successful or not, 1: response content,
    #   2: error messages if any
    def send_request(method, path, query, oauth)
      # Make base_str and signing_key
      base_str = method.to_s.upcase << "&"
      base_str << Helper.percent_encode(HOST + path) << "&"
      hash = query ? oauth.merge(query) : oauth
      array = hash.sort.map {|key, val| Helper.percent_encode(key) + "=" + Helper.percent_encode(val)}
      base_str << Helper.percent_encode(array.join("&"))
      # Sign
      signing_key = String.new(Config.consumer_secret) << "&"
      signing_key << self.oauth_token_secret if hash[:oauth_token]
      signature = Helper.sign(base_str, signing_key)
      signed_oauth = oauth.merge(:oauth_signature => signature)
      # Header
      auth_header = Helper.auth_header(signed_oauth)
      # HTTP request
      uri = URI.parse(HOST + path)
      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = true
      case
      when method.to_s.upcase == "POST"
        request = Net::HTTP::Post.new(uri.request_uri)
        request.set_form_data(query) if query
      when method.to_s.upcase == "GET"
        uri.query = URI.encode_www_form(query) if query
        request = Net::HTTP::Get.new(uri.request_uri)
      end
      request["Authorization"] = auth_header
      ##
      # Might raise SocketError if no internet connection
      response = https.request(request)
      case response.code
      when "200"
        begin
          return true, MultiJson.load(response.body)
        rescue MultiJson::LoadError
          return true, Rack::Utils.parse_nested_query(response.body)
        end
      else
        return false, MultiJson.load(response.body), response.code
      end
    end

    ##
    # Sign oauth params
    def self.sign(base_str, signing_key)
      hex_str = OpenSSL::HMAC.hexdigest(
        OpenSSL::Digest::Digest.new('sha1'),
        signing_key,
        base_str)
      binary_str = Base64.encode64( [hex_str].pack("H*") ).gsub(/\n/, "")
      return Helper.percent_encode( binary_str )
    end

    def self.auth_header(signed_oauth)
      params = signed_oauth.map { |key, val| "#{key}=\"#{val}\"" }
      return "OAuth " << params.join(",")
    end

  end
end
