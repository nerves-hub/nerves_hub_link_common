defmodule NervesHubLinkCommon.UpdateManager.Progress do
  @moduledoc """
  Structure representing the current progress of a firmware update
  """

  defstruct [
    :percent,
    :error,
    :uuid
  ]

  @type t :: %__MODULE__{
          percent: 0..100,
          error: nil | String.t(),
          uuid: String.t()
        }
end
