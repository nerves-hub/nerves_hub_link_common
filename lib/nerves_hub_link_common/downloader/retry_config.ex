defmodule NervesHubLinkCommon.Downloader.RetryConfig do
  @moduledoc """
  Configuration structure for how the Downloader server will
  handle disconnects, errors, timeouts etc
  """

  defstruct [
    # stop trying after this many disconnects
    max_disconnects: 10,

    # attempt a retry after this time
    # if no data comes in after this amount of time, disconnect and retry
    idle_timeout: 60_000,

    # if the total time since this server has started reaches this time,
    # stop trying, give up, disconnect, etc
    # started right when the gen_server starts
    max_timeout: 3_600_000,

    # don't bother retrying until this time has passed
    time_between_retries: 15_000
  ]

  @type t :: %__MODULE__{
          max_disconnects: non_neg_integer(),
          idle_timeout: timeout(),
          max_timeout: timeout(),
          time_between_retries: non_neg_integer()
        }
end
