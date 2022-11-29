class FakeExceptionService
  @@exceptions : Array(Hash(String, Exception)) = [] of Hash(String, Exception)

  def self.clear
    @@exceptions = [] of Hash(String, Exception)
  end

  def self.size
    @@exceptions.size
  end

  def self.exceptions
    @@exceptions
  end

  def self.notify(exception, message)
    @@exceptions << {message => exception}
  end
end
