module Cable
  class Payload
    alias RESULT = String | Int64 | Hash(String, RESULT)
    alias PARAMS = Hash(String, RESULT)

    getter :json
    getter :action
    getter command : String?
    getter identifier : String
    getter channel : String?
    getter channel_params : Hash(String, Cable::Payload::RESULT) = Hash(String, RESULT).new
    getter data : Hash(String, Cable::Payload::RESULT) = Hash(String, RESULT).new

    def initialize(@json : String)
      @parsed_json = JSON.parse(@json)
      @action = ""
      @is_action = false
      @command = @parsed_json["command"].as_s
      @identifier = @parsed_json["identifier"].as_s
      @channel = process_channel
      @channel_params = process_channel_params
      @data = process_data
    end

    def action?
      @is_action
    end

    private def parsed_identifier
      JSON.parse(@parsed_json["identifier"].as_s)
    end

    private def process_channel
      parsed_identifier["channel"].as_s
    end

    private def json_data
      JSON.parse(@parsed_json["data"].as_s) if @parsed_json.as_h.has_key?("data")
    end

    private def process_data
      if jsd = json_data
        params = jsd.as_h.dup
        if deleted_action = params.delete("action")
          @action = deleted_action.as_s
          @is_action = true
        end

        process_hash(params)
      else
        Hash(String, RESULT).new
      end
    end

    private def process_channel_params
      params = parsed_identifier.as_h.dup
      params.delete("channel")

      process_hash(params)
    end

    private def process_hash(params : Hash(String, JSON::Any))
      params_result = Hash(String, RESULT).new

      params.each do |k, v|
        if v.as_s?
          params_result[k] = v.as_s
        elsif v.as_i64?
          params_result[k] = v.as_i64
        elsif v.as_h?
          params_result[k] = process_hash(v)
        end
      end

      params_result
    end

    private def process_hash(hash : JSON::Any)
      process_hash(hash.as_h)
    end
  end
end
