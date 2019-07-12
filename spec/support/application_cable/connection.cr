module ApplicationCable
  class Connection < Cable::Connection
    identified_by identifier

    def connect
      self.identifier = user_id
    end
  end
end
