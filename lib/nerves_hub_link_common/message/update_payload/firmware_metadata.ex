defmodule NervesHubLinkCommon.Message.FirmwareMetadata do
  @moduledoc false

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

  @type t() :: %__MODULE__{
          architecture: String.t(),
          author: String.t() | nil,
          description: String.t() | nil,
          fwup_version: Version.build() | nil,
          misc: String.t() | nil,
          platform: String.t(),
          product: String.t(),
          uuid: binary(),
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
