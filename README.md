# Dyson

Small library to connect to Dyson Pure Cool.

```ruby
# connecting
Dyson.discover_devices
dyson = Dyson::Client.authenticate("your email", "your password")
device = dyson.devices.first
device.connect

# device info
device.network # networking info
device.sensor # sensor data
device.state # state of the system

# actions
device.toggle_power # swtich between on and off
device.toggle_auto # switch between auto and manual
device.toggle_rotating # switch rotation on and off
device.toggle_night_mode # switch night mode on and off
device.fan_speed = 5 # change speed of the fan to 5

device.discconnect
```
