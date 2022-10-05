module Cable
  class RedisPinger
    private getter task : Tasker::Task

    def initialize(@server : Cable::Server)
      @task = Tasker.every(Cable.settings.redis_ping_interval) do
        check_redis_subscribe
        check_redis_publish
      rescue e
        # Restart cable if something happened
        Cable.restart
      end
    end

    def stop
      @task.cancel
    end

    # since @server.redis_subscribe connection is called on a block loop
    # we basically cannot call ping outside of the block
    # instead, we just spin up another new redis connection
    # then publish a special channel/message broadcast
    # the @server.redis_subscribe picks up this special combination
    # and calls ping on the block loop for us
    def check_redis_subscribe
      Cable.server.publish("_internal", "ping")
    end

    def check_redis_publish
      result = @server.redis_publish.run({"ping"})
      Cable::Logger.debug { "Cable::RedisPinger.check_redis_publish -> #{result}" }
    end
  end
end
