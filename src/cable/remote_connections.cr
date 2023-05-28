module Cable
  class RemoteConnections
    def initialize(@server : Cable::Server)
    end

    # Specify the name and value of your connection's `identified_by`
    # ```
    # # e.g.
    # # identified_by :user_id
    # # self.user_id = 1234.to_s
    #
    # where({:user_id, "1234"})
    # ```
    def where(identifier : Tuple(Symbol, String))
      RemoteConnection.new(@server, identifier[1])
    end

    private class RemoteConnection
      def initialize(@server : Cable::Server, @value : String)
      end

      def disconnect
        @server.backend.publish_message(internal_channel, Cable.message(:disconnect))
      end

      private def internal_channel
        "cable_internal/#{@value}"
      end
    end
  end
end
