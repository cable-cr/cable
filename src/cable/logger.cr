module Cable
  class Logger
    @@show : Bool = true

    def self.suppress_output
      @@show = false
    end

    def self.show_output
      @@show = true
    end

    def self.info(message)
      Logger.info message if @@show
    end
  end
end
