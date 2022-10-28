require "tasker"

module Cable
  class RedisPinger
    private getter task : Tasker::Task

    def initialize(@server : Cable::Server)
      @task = Tasker.every(Cable.settings.redis_ping_interval) do
        @server.backend.ping_redis_subscribe
        @server.backend.ping_redis_publish
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
  end
end
