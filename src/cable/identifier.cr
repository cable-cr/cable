require "json"

module Cable
  class Identifier
    JSON.mapping({
      channel: String,
      params:  Hash(String, String)?,
    })
  end
end
