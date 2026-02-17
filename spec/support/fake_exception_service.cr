class FakeExceptionService
  record Report, exception : Exception, message : String, connection : Cable::Connection?
  @@exceptions : Array(Report) = [] of Report

  def self.clear
    @@exceptions = [] of Report
  end

  def self.size
    @@exceptions.size
  end

  def self.exceptions
    @@exceptions
  end

  def self.notify(exception, message, connection = nil)
    @@exceptions << Report.new(exception: exception, message: message, connection: connection)
  end
end
