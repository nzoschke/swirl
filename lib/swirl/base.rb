require 'swirl/helpers'

module Swirl
  ## Errors
  class InvalidRequest < StandardError ; end

  class Base
    include Helpers::Compactor
    include Helpers::Expander

    def initialize(options)
      @aws_access_key_id =
        options[:aws_access_key_id] ||
        (raise ArgumentError, "no aws_access_key_id provided")
      @aws_secret_access_key =
        options[:aws_secret_access_key] ||
        (raise ArgumentError, "no aws_secret_access_key provided")

      @hmac = HMAC::SHA256.new(@aws_secret_access_key)
      @version = options[:version] || "2009-11-30"
    end

    def escape(value)
      CGI.escape(value).gsub(/\+/, "%20")
    end

    def compile_sorted_form_data(query)
      valid = query.reject {|_, v| v.nil? }
      valid.sort.map {|k,v| [k, escape(v)] * "=" } * "&"
    end

    def compile_signature(method, body)
      string_to_sign = [method, @url.host, "/", body] * "\n"
      hmac = @hmac.update(string_to_sign)
      encoded_sig = Base64.encode64(hmac.digest).chomp
      escape(encoded_sig)
    end

    def call(action, query={})
      code, data = call!(action, expand(query))

      case code
      when 200
        compact(data)
      when 400...500
        exception_class = Swirl.const_get(data["ErrorResponse"]["Error"]["Code"]) rescue InvalidRequest
        raise exception_class, data["ErrorResponse"]["Error"]["Message"]
      else
        msg = "unexpected response #{code} -> #{data.inspect}"
        raise InvalidRequest, msg
      end
    end

    def call!(action, query={})
      # Hard coding this here until otherwise needed
      method = "POST"

      query["Action"] = action
      query["AWSAccessKeyId"] = @aws_access_key_id
      query["SignatureMethod"] = "HmacSHA256"
      query["SignatureVersion"] = "2"
      query["Timestamp"] = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      query["Version"] = @version

      body = compile_sorted_form_data(query)
      body += "&" + ["Signature", compile_signature(method, body)].join("=")

      response = post(body)

      if ENV["SWIRL_LOG"]
        puts response.body
      end

      data = Crack::XML.parse(response.body)
      [response.code.to_i, data]
    end

    def post(body)
      headers = { "Content-Type" => "application/x-www-form-urlencoded" }

      http = Net::HTTP.new(@url.host, @url.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      request = Net::HTTP::Post.new(@url.request_uri, headers)
      request.body = body

      http.request(request)
    end

  end
end