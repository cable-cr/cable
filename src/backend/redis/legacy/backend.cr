# On redis shard it tries to convert the return of command to Nil
# When returning an array, it raises an exception
# So we monkey patch to run the command, ignore it, and return Nil
{% if Redis.class? %}
  # :nodoc:
  class Redis
    module CommandExecution
      module ValueOriented
        def void_command(request : Request) : Nil
          command(request)
        end
      end
    end

    # Needs access to connection so we can subscribe to
    # multiple channels
    def _connection : Redis::Connection
      connection
    end
  end

  module Cable
    # :nodoc:
    @[Deprecated("The RedisLegacyBackend will be removed in a future version")]
    class RedisLegacyBackend < Cable::BackendCore
      getter redis_subscribe : Redis = Redis.new(url: Cable.settings.url)
      getter redis_publish : Redis::PooledClient | Redis do
        if Cable.settings.pool_redis_publish
          Redis::PooledClient.new(
            url: Cable.settings.url,
            pool_size: Cable.settings.redis_pool_size,
            pool_timeout: Cable.settings.redis_pool_timeout
          )
        else
          Redis.new(url: Cable.settings.url)
        end
      end

      # connection management
      def subscribe_connection : Redis
        redis_subscribe
      end

      def publish_connection : Redis::PooledClient | Redis
        redis_publish
      end

      def close_subscribe_connection
        return if redis_subscribe.nil?

        request = Redis::Request.new
        request << "unsubscribe"
        redis_subscribe._connection.send(request)
        redis_subscribe.close
      end

      def close_publish_connection
        return if redis_publish.nil?

        redis_publish.close
      end

      # internal pub/sub
      def open_subscribe_connection(channel)
        return if redis_subscribe.nil?

        redis_subscribe.subscribe(channel) do |on|
          on.message do |channel, message|
            if channel == "_internal" && message == "ping"
              Cable::Logger.debug { "Cable::Server#subscribe -> PONG" }
            elsif channel == "_internal" && message == "debug"
              Cable.server.debug
            else
              Cable.server.fiber_channel.send({channel, message})
              Cable::Logger.debug { "Cable::Server#subscribe channel:#{channel} message:#{message}" }
            end
          end
        end
      end

      # external pub/sub
      def publish_message(stream_identifier : String, message : String)
        return if redis_publish.nil?

        redis_publish.publish(stream_identifier, message)
      end

      # channel management
      def subscribe(stream_identifier : String)
        return if redis_subscribe.nil?

        request = Redis::Request.new
        request << "subscribe"
        request << stream_identifier
        redis_subscribe._connection.send(request)
      end

      def unsubscribe(stream_identifier : String)
        return if redis_subscribe.nil?

        request = Redis::Request.new
        request << "unsubscribe"
        request << stream_identifier
        redis_subscribe._connection.send(request)
      end

      # ping/pong

      def ping_redis_subscribe
        Cable.server.publish("_internal", "ping")
      end

      def ping_redis_publish
        request = Redis::Request.new
        request << "ping"
        result = redis_subscribe._connection.send(request)
        Cable::Logger.debug { "Cable::RedisPinger.ping_redis_publish -> #{result}" }
      end
    end
  end
{% end %}
