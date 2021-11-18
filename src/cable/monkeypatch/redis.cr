# On redis shard it tries to convert the return of command to Nil
# When returning an array, it raises an exception
# So we monkey patch to run the command, ignore it, and return Nil
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
