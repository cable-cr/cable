module ApplicationCable
  class Connection < Cable::Connection
    def connect
      self.current_user = user_id
    end
  end
end
