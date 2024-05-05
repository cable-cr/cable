require "tasker"

module Cable
  class BackendPinger
    private getter task : Tasker::Task

    def initialize(@server : Cable::Server)
      @task = Tasker.every(Cable.settings.backend_ping_interval) do
        @server.backend.ping_subscribe_connection
        @server.backend.ping_publish_connection
      rescue e
        stop
        Cable::Logger.error { "Cable::BackendPinger Exception: #{e.class.name} -> #{e.message}" }
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
