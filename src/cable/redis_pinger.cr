require "tasker"

module Cable
  class RedisPinger
    private getter task : Tasker::Task

    def initialize(@server : Cable::Server)
      @task = Tasker.every(Cable.settings.redis_ping_interval) do
        check_redis_subscribe
        check_redis_publish
      rescue e
        Cable::Logger.error { "Cable::RedisPinger Exception: #{e.class.name} -> #{e.message}" }
        # Restart cable if something happened
        Cable.server.count_error!
        Cable.restart if Cable.server.restart?
      end
    end

    def stop
      @task.cancel
    end

    def check_redis_subscribe
      Cable.server.publish("_internal", "ping")
    end

    def check_redis_publish
      request = Redis::Request.new
      request << "ping"
      result = @server.redis_subscribe._connection.send(request)
      Cable::Logger.debug { "Cable::RedisPinger.check_redis_publish -> #{result}" }
    end
  end
end
