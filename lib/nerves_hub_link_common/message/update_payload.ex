defmodule NervesHubLinkCommon.Message.UpdatePayload do
  @moduledoc false

  alias NervesHubLinkCommon.Message.FirmwareMetadata

  defstruct update_available: false,
            firmware_url: nil,
            firmware_meta: nil

  @typedoc """
  Payload that gets dispatched down to devices upon an update

  `firmware_url` and `firmware_meta` are only available
  when `update_available` is true.
  """
  @type t() :: %__MODULE__{
          update_available: boolean(),
          firmware_url: String.t() | nil,
          firmware_meta: FirmwareMetadata.t() | nil
        }

  @doc "Parse an update message from NervesHub"
  @spec parse(map()) :: t()
  def parse(params) do
    firmware_meta =
      if params["update_available"] do
        FirmwareMetadata.parse(params["firmware_meta"])
      end

    firmware_url =
      if params["firmware_url"] do
        URI.parse(params["firmware_url"])
      end

    %__MODULE__{
      update_available: params["update_available"],
      firmware_url: firmware_url,
      firmware_meta: firmware_meta
    }
  end
end
