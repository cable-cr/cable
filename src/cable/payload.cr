module Cable
  struct Payload
    include JSON::Serializable
    include JSON::Serializable::Unmapped
    alias RESULT = String | Int64 | Hash(String, RESULT)
    alias PARAMS = Hash(String, RESULT)

    module IdentifierConverter
      def self.from_json(value : JSON::PullParser) : Indentifier
        key = value.read_string
        i = Indentifier.from_json(key)
        i.key = key
        i
      end

      def self.to_json(value : Indentifier, json : JSON::Builder) : Nil
        json.string(value.to_json)
      end
    end

    struct Indentifier
      include JSON::Serializable
      include JSON::Serializable::Unmapped

      property channel : String

      # This is the original JSON used to parse this
      # It's used as a unique key to map the different channels
      @[JSON::Field(ignore: true)]
      property key : String = ""
    end

    @[JSON::Field]
    getter command : String

    @[JSON::Field(converter: Cable::Payload::IdentifierConverter)]
    getter identifier : Indentifier

    @[JSON::Field(ignore: true)]
    getter action : String = ""

    # After the Payload is deserialized, parse the data.
    # This will ensure we know if it's an action.
    def after_initialize
      data
    end

    def channel : String
      identifier.channel
    end

    def action? : Bool
      !action.presence.nil?
    end

    @[JSON::Field(ignore: true)]
    @_channel_params : Hash(String, RESULT)? = nil

    # These are the additional data sent with the identifier
    # e.g. `{channel: "RoomChannel", room_id: 1}`
    # ```
    # channel_params["room_id"] # => 1
    # ```
    def channel_params : Hash(String, RESULT)
      if @_channel_params.nil?
        @_channel_params = process_hash(identifier.json_unmapped)
      else
        @_channel_params.as(Hash(String, RESULT))
      end
    end

    @[JSON::Field(ignore: true)]
    @_data : Hash(String, RESULT)? = nil

    def data : Hash(String, RESULT)
      if @_data.nil?
        if unmapped_data = json_unmapped["data"]?
          @_data = process_data(unmapped_data.as_s)
        else
          @_data = no_data
        end
      else
        @_data.as(Hash(String, RESULT))
      end
    end

    private def no_data : Hash(String, RESULT)
      Hash(String, RESULT).new
    end

    private def process_hash(_params : Nil)
      no_data
    end

    private def process_hash(params : Hash(String, JSON::Any))
      params_result = Hash(String, RESULT).new

      params.each do |k, v|
        if strval = v.as_s?
          params_result[k] = strval
        elsif intval = v.as_i64?
          params_result[k] = intval
        elsif hshval = v.as_h?
          params_result[k] = process_hash(hshval)
        end
      end

      params_result
    end

    private def process_data(data_string : String)
      json_data = JSON.parse(data_string).as_h?
      hash = process_hash(json_data)
      @action = hash.delete("action").to_s
      hash
    end
  end
end
