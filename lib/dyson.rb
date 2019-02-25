require "dyson/version"
require "dyson/client"
require "dyson/device"

require "excon"
require "dnssd"
require "mqtt"

require "json"
require "base64"
require "openssl"
require "securerandom"
require "readline"
require "time"

module Dyson
  def self.services
    @services_semaphore ||= Mutex.new
    @services_semaphore.synchronize { @services ||= {} }
  end

  def self.find_service(serial)
    services[serial]
  end

  def self.discover_devices
    DNSSD.browse("_dyson_mqtt._tcp.") do |service|
      serial = service.name.split("_", 2).last
      services[serial] = service
    end

    true
  end
end
