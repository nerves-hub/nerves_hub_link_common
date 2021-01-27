# NervesHubLinkCommon

Common library that should be shared between
the [websocket](https://github.com/nerves-hub/nerves_hub_link) and [http](https://github.com/nerves-hub/nerves_hub_link_http)
connections.

Handles resumable HTTP streams to fwup.

**NOTE**

You probably don't need this library directly. See the above linked libraries.

## Usage

The main API to this application is `NervesHubLinkCommon.UpdateManager`.
It is meant to be started as a child in a supervision tree:

```elixir
require Logger
alias NervesHubLinkCommon.{UpdateManager, FwupConfig}

def handle_fwup_message({:ok, _status, message}), do: Logger.info("Firmware update complete: #{message} going down for reboot...")
def handle_fwup_message({:warning, _status, message}), do: Logger.warn("Firmware update warning: #{message}")
def handle_fwup_message({:error, _status, message}), do: Logger.error("Firmware update failed: #{message}")
def handle_fwup_message({:progress, percent}), do: Logger.error("Firmware update progress: #{percent}%")

def update_available(%{"firmware_url" => _}) do
  if SomeExternalApi.is_now_a_good_time_for_a_firmware_update?() do
    :apply
  else
    {:reschedule, 60_000}
  end
end

def init(_) do
  fwup_config = %FwupConfig{
      fwup_public_keys: ["Qqyf/7JrIt06+xzvF6a5CgNj8/CZfHUemTa32R8effM="],
      fwup_devpath: "/dev/mmcblk0p1",
      handle_fwup_message: &handle_fwup_message/1,
      update_available: &update_available/1
  }
  children = [{UpdateManager, fwup_config}]
  Supervisor.init(children, [strategy: :one_for_one])
end
```
