defmodule NervesHubFwup.Args do
  defstruct fwup_public_keys: [],
            fwup_devpath: "/dev/mmcblk0",
            handle_fwup_message: nil,
            update_available: nil

  @type fwup_message ::
          {:progress, 0 | pos_integer()}
          | {:warning, 0 | pos_integer(), String.t()}
          | {:error, 0 | pos_integer(), String.t()}
          | {:ok, 0 | pos_integer(), String.t()}

  @type handle_fwup_message_fun() :: (fwup_message -> any)

  @type update_available_fun() :: (map() -> any)

  @type t :: %NervesHubFwup.Args{
          fwup_public_keys: [String.t()],
          fwup_devpath: Path.t(),
          handle_fwup_message: handle_fwup_message_fun,
          update_available: update_available_fun
        }
end
