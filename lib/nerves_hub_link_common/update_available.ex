defmodule NervesHubLinkCommon.UpdateAvailable do
  defmodule FirmwareMetadata do
    @moduledoc "Metadata about an update"
    defstruct [
      :architecture,
      :author,
      :description,
      :fwup_version,
      :id,
      :misc,
      :platform,
      :product,
      :uuid,
      :vcs_identifier,
      :version
    ]

    @type t :: %__MODULE__{
            architecture: String.t(),
            author: String.t() | nil,
            description: String.t() | nil,
            fwup_version: Version.build() | nil,
            id: Ecto.UUID.t(),
            misc: String.t() | nil,
            platform: String.t(),
            product: String.t(),
            uuid: Ecto.UUID.t(),
            vcs_identifier: String.t() | nil,
            version: Version.build()
          }

    @spec parse(map()) :: t()
    def parse(params) do
      %__MODULE__{
        architecture: params["architecture"],
        author: params["author"],
        description: params["description"],
        fwup_version: params["fwup_version"],
        id: params["id"],
        misc: params["misc"],
        platform: params["platform"],
        product: params["product"],
        uuid: params["uuid"],
        vcs_identifier: params["vcs_identifier"],
        version: params["version"]
      }
    end
  end

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

  @doc "Validates the payload from NervesHub"
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
