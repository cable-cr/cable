require "tasker"

module Cable
  class WebsocketPinger
    class PingStoppedException < Exception; end

    @@seconds : Int32 | Float64 = 3
    @task : Tasker::Task

    def self.run_every(value : Int32 | Float64, &)
      @@seconds = value

      yield

      @@seconds = 3
    end

    def self.build(socket : HTTP::WebSocket)
      self.new(socket)
    end

    def self.seconds
      @@seconds
    end

    def initialize(@socket : HTTP::WebSocket)
      @task = Tasker.every(Cable::WebsocketPinger.seconds.seconds) do
        raise PingStoppedException.new("Stopped") if @socket.closed?
        @socket.send({type: Cable.message(:ping), message: Time.utc.to_unix}.to_json)
      end
    end

    def stop
      @task.cancel
    end
  end
end
