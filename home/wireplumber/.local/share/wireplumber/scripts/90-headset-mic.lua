-- The 3.5 mm microphone and the internal microphone share one audio source.
-- Choose the external route whenever its jack is detected. Leave unavailable
-- jacks to the normal policy so the internal microphone remains the fallback.
local cutils = require ("common-utils")
local devinfo = require ("device-info-cache")

SimpleEventHook {
  name = "device/prefer-headset-mic",
  before = { "device/find-stored-routes", "device/find-best-routes" },
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-routes" },
      Constraint { "profile.active-device-ids", "is-present" },
    },
  },
  execute = function (event)
    local device = event:get_subject ()
    local info = devinfo:get_device_info (device)
    if not info or info.name ~= "alsa_card.pci-0000_00_1f.3" then
      return
    end

    local active_ids = Json.Raw (
        event:get_properties ()["profile.active-device-ids"]):parse ()
    local selected = event:get_data ("selected-routes") or Properties ()

    for _, device_id in ipairs (active_ids) do
      for _, route in pairs (info.route_infos) do
        if route.direction == "Input" and
            route.name == "analog-input-mic" and
            route.available == "yes" and
            cutils.arrayContains (route.devices, device_id) and
            (route.profiles == nil or
             cutils.arrayContains (route.profiles, info.active_profile)) then
          selected[tostring (device_id)] =
              Json.Object { index = route.index }:to_string ()
          break
        end
      end
    end

    event:set_data ("selected-routes", selected)
  end,
}:register ()
