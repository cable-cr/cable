require "json"

module Cable
  class Payload
    JSON.mapping({
      command:    String,
      identifier: String,
      data:       String?,
    })
  end
end
