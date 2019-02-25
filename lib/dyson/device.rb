module Dyson
  class Device
    IV = [0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0].pack("C*")
    KEY = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20].pack("C*")

    def initialize(attributes)
      @semaphore = Mutex.new
      @id = "dyson_#{SecureRandom.hex(8)}"
      @attributes = attributes
      @credentials = decrypt_credentials
      @networked = false
      @network = {}
      @sensitivity = 1.0
      @state = {}
      @sensor = {}
    end

    attr_reader :id, :attributes, :credentials, :sensor, :state

    def connected?
      unless @client
        return false
      end

      @client.connected?
    end

    def connect
      @client = MQTT::Client.connect({
        host: address,
        port: port,
        username: serial,
        password: password,
        client_id: id,
      })

      Thread.new do
        @client.get do |topic, message|
          data = JSON.parse(message)
          type = data.delete("msg")

          apply(type, data)
        end
      end

      @client.subscribe("#{mqtt_prefix}/#{serial}/status/current")

      refresh

      true
    end

    def publish(message, data = nil)
      unless @client
        raise "not connected"
      end

      body = { msg: message, time: Time.now.iso8601 }

      if data
        body[:data] = data
      end

      @client.publish("#{mqtt_prefix}/#{serial}/command", JSON.generate(body))
    end

    def refresh
      publish("REQUEST-CURRENT-STATE")
    end

    def disconnect
      unless @client
        return true
      end

      @client.disconnect
      @client = nil

      true
    end

    def network
      if @networked
        return @network
      end

      service = Dyson.services[serial]

      unless service
        return({})
      end

      reply = service.resolve

      unless reply
        return({})
      end

      @networked = true

      name = service.name
      mqtt_prefix = name.split("_", 2).first
      host = reply.target
      port = reply.port
      address = Socket.getaddrinfo(host, port)[0][2]

      @network = {
        name: name,
        mqtt_prefix: mqtt_prefix,
        host: host,
        port: port,
        address: address,
      }
    end

    def address
      network[:address]
    end

    def port
      network[:port]
    end

    def mqtt_prefix
      network[:mqtt_prefix]
    end

    def temperature
      @sensor[:temperature]
    end

    def humidity
      @sensor[:humidity]
    end

    def nitrogen
      @sensor[:nitrogen]
    end

    def voc
      @sensor[:voc]
    end

    def pm25
      @sensor[:pm25]
    end

    def pm10
      @sensor[:pm10]
    end

    def power
      @state[:power]
    end

    def auto
      @state[:auto]
    end

    def rotating
      @state[:rotating]
    end

    def air_flow
      @state[:air_flow]
    end

    def rotation_from
      @state[:rotation_from]
    end

    def rotation_to
      @state[:rotation_to]
    end

    def fan_speed
      @state[:fan_speed]
    end

    def fan
      @state[:fan]
    end

    def night_mode
      @state[:night_mode]
    end

    def power=(state)
      publish("STATE-SET", fpwr: state.to_s.upcase)
    end

    def fan_speed=(speed)
      publish("STATE-SET", fnsp: speed.to_s.upcase)
    end

    def auto=(state)
      publish("STATE-SET", auto: state.to_s.upcase)
    end

    def night_mode=(state)
      publish("STATE-SET", nmod: state.to_s.upcase)
    end

    def rotating=(state)
      publish("STATE-SET", oson: state.to_s.upcase)
    end

    def toggle_power
      if power != :on
        self.power = :on
      else
        self.power = :off
      end
    end

    def toggle_night_mode
      if night_mode != :on
        self.night_mode = :on
      else
        self.night_mode = :off
      end
    end

    def toggle_auto
      if auto != :on
        self.auto = :on
      else
        self.auto = :off
      end
    end

    def toggle_rotating
      if rotating != :on
        self.rotating = :on
      else
        self.rotating = :off
      end
    end

    def name
      @attributes["Name"]
    end

    def serial
      @credentials["serial"]
    end

    def password
      @credentials["apPasswordHash"]
    end

    private

    def apply(type, data)
      @semaphore.synchronize do
        case type
        when "CURRENT-STATE"
          update_state(data)
        when "LOCATION"
          @state[:position] = data["apos"].to_i
        when "ENVIRONMENTAL-CURRENT-SENSOR-DATA"
          update_sensor(data)
        when "STATE-CHANGE"
          refresh
        end
      end
    end

    def update_state(data)
      @state = @state.merge({
        power: data["product-state"]["fpwr"].downcase.to_sym,
        auto: data["product-state"]["auto"].downcase.to_sym,
        rotating: data["product-state"]["oscs"].downcase.to_sym,
        air_flow: data["product-state"]["fdir"].downcase.to_sym,
        rotation_from: data["product-state"]["osal"].to_i,
        rotation_to: data["product-state"]["osau"].to_i,
        fan_speed: parse_fan_speed(data["product-state"]["fnsp"]),
        fan: data["product-state"]["fnst"].downcase.to_sym,
        night_mode: data["product-state"]["nmod"].downcase.to_sym,
      })
    end

    def update_sensor(data)
      @sensor = @sensor.merge({
        temperature: calculate_temperature(data["data"]["tact"]),
        humidity: data["data"]["hact"].to_i,
        pm25: data["data"]["p25r"].to_i,
        pm10: data["data"]["p10r"].to_i,
        voc: data["data"]["va10"].to_i,
        nitrogen: data["data"]["noxl"].to_i,
      })
    end

    def calculate_temperature(temperature)
      ((temperature.to_f / 10) - 273.15).round
    end

    def parse_fan_speed(speed)
      speed == "AUTO" ? :auto : speed.to_i
    end

    def decrypt_credentials
      cipher = OpenSSL::Cipher.new("AES-256-CBC")
      cipher.decrypt
      cipher.iv = IV
      cipher.key = KEY

      plain = cipher.update(Base64.decode64(@attributes["LocalCredentials"])) + cipher.final

      JSON.parse(plain)
    end
  end
end