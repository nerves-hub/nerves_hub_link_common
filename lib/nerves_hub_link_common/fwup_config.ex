defmodule NervesHubLinkCommon.FwupConfig do
  @moduledoc """
  Config structure responsible for handling callbacks from FWUP,
  applying a fwupdate, and storing fwup task configuration
  """
  alias NervesHubLinkCommon.UpdateAvailable

  defstruct fwup_public_keys: [],
            fwup_devpath: "/dev/mmcblk0",
            handle_fwup_message: nil,
            update_available: nil,
            journal_location: "/tmp/"

  @typedoc """
  `handle_fwup_message` will be called with this data
  """
  @type fwup_message ::
          {:progress, non_neg_integer()}
          | {:warning, non_neg_integer(), String.t()}
          | {:error, non_neg_integer(), String.t()}
          | {:ok, non_neg_integer(), String.t()}

  @typedoc """
  Callback that will be called during the lifecycle of a fwupdate being applied
  """
  @type handle_fwup_message_fun() :: (fwup_message -> any)

  @typedoc """
  Called when an update has been dispatched via `NervesHubLinkCommon.UpdateManager.apply_update/2`
  """
  @type update_available_fun() ::
          (UpdateAvailable.t() -> :ignore | {:reschedule, timeout()} | :apply)

  @type t :: %__MODULE__{
          fwup_public_keys: [String.t()],
          fwup_devpath: Path.t(),
          journal_location: Path.t(),
          handle_fwup_message: handle_fwup_message_fun,
          update_available: update_available_fun
        }

  @doc "Raises an ArgumentError on invalid arguments"
  def validate!(%__MODULE__{} = args) do
    args
    |> validate_fwup_public_keys!()
    |> validate_fwup_devpath!()
    |> validate_handle_fwup_message!()
    |> validate_update_available!()
    |> validate_journal_location!()
  end

  defp validate_fwup_public_keys!(%__MODULE__{fwup_public_keys: list} = args) when is_list(list),
    do: args

  defp validate_fwup_public_keys!(%__MODULE__{}),
    do: raise(ArgumentError, message: "invalid arg: fwup_public_keys")

  defp validate_fwup_devpath!(%__MODULE__{fwup_devpath: devpath} = args) when is_binary(devpath),
    do: args

  defp validate_fwup_devpath!(%__MODULE__{}),
    do: raise(ArgumentError, message: "invalid arg: fwup_devpath")

  defp validate_handle_fwup_message!(%__MODULE__{handle_fwup_message: handle_fwup_message} = args)
       when is_function(handle_fwup_message, 1),
       do: args

  defp validate_handle_fwup_message!(%__MODULE__{}),
    do: raise(ArgumentError, message: "handle_fwup_message function signature incorrect")

  defp validate_update_available!(%__MODULE__{update_available: update_available} = args)
       when is_function(update_available, 1),
       do: args

  defp validate_update_available!(%__MODULE__{}),
    do: raise(ArgumentError, message: "update_available function signature incorrect")

  defp validate_journal_location!(%__MODULE__{journal_location: loc} = args) when is_binary(loc),
    do: args

  defp validate_journal_location!(%__MODULE__{}),
    do: raise(ArgumentError, message: "invalid arg: journal_location")
end
