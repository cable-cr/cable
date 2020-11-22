# On redis shard it tries to convert the return of command to Nil
# When returning an array, it raises an exception
# So we mokeypatch to run the command, ignore it, and retun Nil
class Redis
  module CommandExecution
    module ValueOriented
      def void_command(request : Request) : Nil
        command(request)
        Nil
      end
    end
  end
end
