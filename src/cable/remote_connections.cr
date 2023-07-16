module Cable
  class RemoteConnections
    def initialize(@server : Cable::Server)
    end

    # Specify the value of your connection's `identified_by`
    # ```
    # # e.g.
    # # identified_by :user_id
    # # self.user_id = 1234.to_s
    #
    # find("1234")
    # ```
    # NOTE: This code may run on a different machine than where the `@server.connections`
    # is actually sitting in memory. For this reason, we just pass the value right through
    # the backend (i.e. redis), and let that broadcast out to all running instances.
    def find(identifier : String) : RemoteConnection
      RemoteConnection.new(@server, identifier)
    end

    private class RemoteConnection
      def initialize(@server : Cable::Server, @value : String)
      end

      def disconnect : Nil
        @server.backend.publish_message(internal_channel, Cable.message(:disconnect))
      end

      private def internal_channel : String
        "cable_internal/#{@value}"
      end
    end
  end
end
