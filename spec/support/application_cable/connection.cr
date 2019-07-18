module ApplicationCable
  class Connection < Cable::Connection
    identified_by :identifier

    def connect
      self.identifier = token
    end
  end
end
