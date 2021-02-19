module ApplicationCable
  class Connection < Cable::Connection
    identified_by :identifier

    def connect
      if tk = token
        self.identifier = tk
      end
    end
  end
end
