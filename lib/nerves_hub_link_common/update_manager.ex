defmodule NervesHubLinkCommon.UpdateManager do
  @moduledoc """
  GenServer responsible for brokering messages between:
    * an external controlling process
    * FWUP
    * HTTP

  Should be started in a supervision tree
  """

  require Logger
  use GenServer

  alias NervesHubLinkCommon.{
    Downloader,
    Downloader.RetryConfig,
    FwupConfig,
    UpdateAvailable
  }

  defmodule State do
    @moduledoc """
    Structure for the state of the `UpdateManager` server.
    Contains types that describe status and different states the
    `UpdateManager` can be in
    """

    @type status ::
            :idle
            | {:fwup_error, String.t()}
            | :update_rescheduled
            | {:updating, integer()}

    @type t :: %__MODULE__{
            status: status(),
            update_reschedule_timer: nil | :timer.tref(),
            download: nil | GenServer.server(),
            fwup: nil | GenServer.server(),
            fwup_config: FwupConfig.t(),
            retry_config: RetryConfig.t()
          }

    @type download_started :: %__MODULE__{
            status: {:updating, integer()} | {:fwup_error, String.t()},
            update_reschedule_timer: nil,
            download: GenServer.server(),
            fwup: GenServer.server(),
            fwup_config: FwupConfig.t()
          }

    @type download_rescheduled :: %__MODULE__{
            status: :update_rescheduled,
            update_reschedule_timer: :timer.tref(),
            download: nil,
            fwup: nil,
            fwup_config: FwupConfig.t()
          }

    defstruct status: :idle,
              update_reschedule_timer: nil,
              fwup: nil,
              download: nil,
              fwup_config: nil,
              retry_config: nil
  end

  @doc """
  Must be called when an update payload is dispatched from
  NervesHub. the map must contain a `"firmware_url"` key.
  """
  @spec apply_update(GenServer.server(), map()) :: State.status()
  def apply_update(manager \\ __MODULE__, %{"firmware_url" => _} = params) do
    update_available = UpdateAvailable.parse(params)
    GenServer.call(manager, {:apply_update, update_available})
  end

  @doc """
  Returns the current status of the update manager
  """
  @spec status(GenServer.server()) :: State.status()
  def status(manager \\ __MODULE__) do
    GenServer.call(manager, :status)
  end

  @doc false
  def child_spec(%FwupConfig{} = fwup_config) do
    %{
      start: {__MODULE__, :start_link, [fwup_config, %RetryConfig{}, [name: __MODULE__]]},
      id: __MODULE__
    }
  end

  def child_spec(%FwupConfig{} = fwup_config, %RetryConfig{} = retry_config) do
    %{
      start: {__MODULE__, :start_link, [fwup_config, retry_config, [name: __MODULE__]]},
      id: __MODULE__
    }
  end

  @doc false
  def start_link(%FwupConfig{} = fwup_config, %RetryConfig{} = retry_config, opts \\ []) do
    GenServer.start_link(__MODULE__, {fwup_config, retry_config}, opts)
  end

  @impl GenServer
  def init({%FwupConfig{} = fwup_config, %RetryConfig{} = retry_config}) do
    fwup_config = FwupConfig.validate!(fwup_config)
    {:ok, %State{fwup_config: fwup_config, retry_config: retry_config}}
  end

  @impl GenServer
  def handle_call({:apply_update, %UpdateAvailable{} = update}, _from, %State{} = state) do
    state = maybe_update_firmware(update, state)
    {:reply, state.status, state}
  end

  def handle_call(:status, _from, %State{} = state) do
    {:reply, state.status, state}
  end

  @impl GenServer
  def handle_info({:update_reschedule, response}, state) do
    {:noreply, maybe_update_firmware(response, %State{state | update_reschedule_timer: nil})}
  end

  # messages from FWUP
  def handle_info({:fwup, {:ok, 0, _message} = full_message}, state) do
    Logger.info("[NervesHubLink] FWUP Finished")
    _ = state.fwup_config.handle_fwup_message.(full_message)
    {:noreply, %State{state | fwup: nil}}
  end

  def handle_info({:fwup, message}, state) do
    _ = state.fwup_config.handle_fwup_message.(message)

    case message do
      {:progress, percent} ->
        {:noreply, %State{state | status: {:updating, percent}}}

      {:error, _, message} ->
        {:noreply, %State{state | status: {:fwup_error, message}}}

      _ ->
        {:noreply, state}
    end
  end

  # messages from Downloader
  def handle_info({:download, :complete}, state) do
    Logger.info("[NervesHubLink] Firmware Download complete")
    {:noreply, %State{state | download: nil}}
  end

  def handle_info({:download, {:error, reason}}, state) do
    Logger.error("[NervesHubLink] Nonfatal HTTP download error: #{inspect(reason)}")
    {:noreply, state}
  end

  # Data from the downloader is sent to fwup
  def handle_info({:download, {:data, data}}, state) do
    _ = Fwup.Stream.send_chunk(state.fwup, data)
    {:noreply, state}
  end

  @spec maybe_update_firmware(UpdateAvailable.t(), State.t()) ::
          State.download_started() | State.download_rescheduled() | State.t()
  defp maybe_update_firmware(_data, %State{status: {:updating, _percent}} = state) do
    # Received an update message from NervesHub, but we're already in progress.
    # It could be because the deployment/device was edited making a duplicate
    # update message or a new deployment was created. Either way, lets not
    # interrupt FWUP and let the task finish. After update and reboot, the
    # device will check-in and get an update message if it was actually new and
    # required
    state
  end

  defp maybe_update_firmware(%UpdateAvailable{} = data, %State{} = state) do
    # Cancel an existing timer if it exists.
    # This prevents rescheduled updates`
    # from compounding.
    state = maybe_cancel_timer(state)

    # possibly offload update decision to an external module.
    # This will allow application developers
    # to control exactly when an update is applied.
    case state.fwup_config.update_available.(data) do
      :apply ->
        start_fwup_stream(data, state)

      :ignore ->
        state

      {:reschedule, ms} ->
        timer = Process.send_after(self(), {:update_reschedule, data}, ms)
        Logger.info("[NervesHubLink] rescheduling firmware update in #{ms} milliseconds")
        %{state | status: :update_rescheduled, update_reschedule_timer: timer}
    end
  end

  defp maybe_update_firmware(_, state), do: state

  defp maybe_cancel_timer(%{update_reschedule_timer: nil} = state), do: state

  defp maybe_cancel_timer(%{update_reschedule_timer: timer} = state) do
    _ = Process.cancel_timer(timer)

    %{state | update_reschedule_timer: nil}
  end

  @spec start_fwup_stream(UpdateAvailable.t(), State.t()) :: State.download_started()
  defp start_fwup_stream(%UpdateAvailable{} = update, state) do
    pid = self()
    fun = &send(pid, {:download, &1})

    with {:ok, fwup} <- Fwup.stream(pid, fwup_args(state.fwup_config)),
         {:ok, download} <-
           Downloader.start_download(update.firmware_url, fun, state.retry_config) do
      Logger.info("[NervesHubLink] Downloading firmware: #{update.firmware_url}")
      %State{state | status: {:updating, 0}, download: download, fwup: fwup}
    end
  end

  @spec fwup_args(FwupConfig.t()) :: [String.t()]
  defp fwup_args(%FwupConfig{fwup_public_keys: fwup_public_keys, fwup_devpath: devpath}) do
    args = ["--apply", "--no-unmount", "-d", devpath, "--task", "upgrade"]

    Enum.reduce(fwup_public_keys, args, fn public_key, args ->
      args ++ ["--public-key", public_key]
    end)
  end
end
