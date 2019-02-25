module Dyson
  class Client
    BASE_URL = "https://api.cp.dyson.com"

    def initialize(user, password)
      @user = user
      @password = password
    end

    def self.authenticate(email, password)
      response = Excon.post("#{BASE_URL}/v1/userregistration/authenticate?country=TH", {
        ssl_verify_peer: false,
        headers: { "Accept" => "application/json", "Content-Type" => "application/json" },
        body: JSON.generate(Email: email, Password: password),
      })

      auth = JSON.parse(response.body)

      new(auth["Account"], auth["Password"])
    end

    def devices
      response = Excon.get("#{BASE_URL}/v2/provisioningservice/manifest", {
        ssl_verify_peer: false,
        headers: { "Accept" => "application/json" },
        user: @user,
        password: @password,
      })

      JSON.parse(response.body).map { |attributes| Device.new(attributes) }
    end
  end
end
