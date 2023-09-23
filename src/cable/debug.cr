# messy debug methods out of the way from the main functional logic

module Cable
  module Debug
    def debug_json
      _channels = {} of String => Set(String)

      @channels.each do |k, v|
        _channels[v.first.class.to_s] ||= Set{k}
        _channels[v.first.class.to_s] << k
      end

      {
        "total_conn_chanels"  => Cable::Connection::CHANNELS.size,
        "errors"              => @errors,
        "connections"         => @connections.size,
        "channels"            => @channels.size,
        "channels_mounted"    => _channels,
        "connections_mounted" => @connections.map do |key, connection|
          connections_mounted_channels = [] of Hash(String, String)
          @channels.each do |_, v|
            v.each do |channel|
              next unless channel.connection.connection_identifier == key
              connections_mounted_channels << {
                "channel"  => channel.class.to_s,
                "key"      => channel.stream_identifier,
                "rejected" => channel.subscription_rejected?.to_s,
              }
            end
          end

          {
            "key"        => key,
            "identifier" => connection.identifier,
            "closed"     => connection.closed?.to_s,
            "rejected"   => connection.connection_rejected?.to_s,
            "started_at" => connection.started_at.to_s("%Y-%m-%dT%H:%M:%S.%6N"),
            "channels"   => connections_mounted_channels,
          }
        end,
      }
    end

    def debug
      Cable::Logger.debug { "-" * 80 }
      Cable::Logger.debug { "Some Good Information" }
      Cable::Logger.debug { "Connections" }
      @connections.each do |k, _v|
        Cable::Logger.debug { "Connection Key: #{k}" }
      end
      Cable::Logger.debug { "Channels" }
      @channels.each do |k, v|
        Cable::Logger.debug { "Channel Key: #{k}" }
        Cable::Logger.debug { "Channels" }
        v.each do |channel|
          Cable::Logger.debug { "From Channel: #{channel.connection.connection_identifier}" }
          Cable::Logger.debug { "Params: #{channel.params}" }
          Cable::Logger.debug { "ID: #{channel.identifier}" }
          Cable::Logger.debug { "Stream ID:: #{channel.stream_identifier}" }
        end
      end
      Cable::Logger.debug { "-" * 80 }
    end
  end
end
