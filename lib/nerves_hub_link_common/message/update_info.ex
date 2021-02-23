defmodule NervesHubLinkCommon.Message.UpdateInfo do
  @moduledoc """
  """

  alias NervesHubLinkCommon.Message.FirmwareMetadata

  defstruct firmware_url: nil,
            firmware_meta: nil

  @typedoc """
  Payload that gets dispatched down to devices upon an update

  `firmware_url` and `firmware_meta` are only available
  when `update_available` is true.
  """
  @type t() :: %__MODULE__{
          firmware_url: String.t() | nil,
          firmware_meta: FirmwareMetadata.t() | nil
        }

  @doc "Parse an update message from NervesHub"
  @spec parse(map()) :: {:ok, t()} | {:error, :bad_firmware_url | :invalid_params}
  def parse(%{"firmware_meta" => %{} = meta, "firmware_url" => url}) do
    with {:ok, firmware_meta} <- FirmwareMetadata.parse(meta),
         %URI{} = url <- URI.parse(url) do
      {:ok,
       %__MODULE__{
         firmware_url: url,
         firmware_meta: firmware_meta
       }}
    else
      :error -> {:error, :bad_firmware_url}
      {:error, reason} -> {:error, reason}
    end
  end

  def parse(_), do: {:error, :invalid_params}
end
