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

  alias NervesHubLinkCommon.{Downloader, FwupConfig}
  alias NervesHubLinkCommon.Message.UpdateInfo

  defmodule State do
    @moduledoc """
    Structure for the state of the `UpdateManager` server.
    Contains types that describe status and different states the
    `UpdateManager` can be in
    """

    @type uuid :: String.t()

    @type status ::
            :idle
            | {:fwup_error, String.t()}
            | :update_rescheduled
            | {:updating, uuid, integer()}

    @type t :: %__MODULE__{
            status: status(),
            update_reschedule_timer: nil | :timer.tref(),
            download: nil | GenServer.server(),
            fwup: nil | GenServer.server(),
            fwup_config: FwupConfig.t(),
            update_info: nil | UpdateInfo.t()
          }

    @type download_started :: %__MODULE__{
            status: {:updating, uuid, integer()} | {:fwup_error, String.t()},
            update_reschedule_timer: nil,
            download: GenServer.server(),
            fwup: GenServer.server(),
            fwup_config: FwupConfig.t(),
            update_info: UpdateInfo.t()
          }

    @type download_rescheduled :: %__MODULE__{
            status: :update_rescheduled,
            update_reschedule_timer: :timer.tref(),
            download: nil,
            fwup: nil,
            fwup_config: FwupConfig.t(),
            update_info: nil
          }

    defstruct status: :idle,
              update_reschedule_timer: nil,
              fwup: nil,
              download: nil,
              fwup_config: nil,
              update_info: nil
  end

  @doc """
  Must be called when an update payload is dispatched from
  NervesHub. the map must contain a `"firmware_url"` key.
  """
  @spec apply_update(GenServer.server(), UpdateInfo.t()) :: State.status()
  def apply_update(manager \\ __MODULE__, %UpdateInfo{} = update_info) do
    GenServer.call(manager, {:apply_update, update_info})
  end

  @doc """
  Returns the current status of the update manager
  """
  @spec status(GenServer.server()) :: State.status()
  def status(manager \\ __MODULE__) do
    GenServer.call(manager, :status)
  end

  @doc false
  def child_spec(%FwupConfig{} = args) do
    %{
      start: {__MODULE__, :start_link, [args, [name: __MODULE__]]},
      id: __MODULE__
    }
  end

  @doc false
  def start_link(%FwupConfig{} = args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl GenServer
  def init(%FwupConfig{} = fwup_config) do
    fwup_config = FwupConfig.validate!(fwup_config)
    {:ok, %State{fwup_config: fwup_config}}
  end

  @impl GenServer
  def handle_call({:apply_update, %UpdateInfo{} = update}, _from, %State{} = state) do
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
    _ = state.fwup_config.handle_fwup_message.(full_message, state.update_info.firmware_meta)
    {:noreply, %State{state | fwup: nil, update_info: nil}}
  end

  def handle_info({:fwup, message}, state) do
    _ = state.fwup_config.handle_fwup_message.(message, state.update_info.firmware_meta)

    case message do
      {:progress, percent} ->
        status = {:updating, state.update_info.firmware_meta.uuid, percent}
        {:noreply, %State{state | status: status}}

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

  @spec maybe_update_firmware(UpdateInfo.t(), State.t()) ::
          State.download_started() | State.download_rescheduled() | State.t()

  defp maybe_update_firmware(
         %UpdateInfo{} = _update_info,
         %State{status: {:updating, _uuid, _percent}} = state
       ) do
    # Received an update message from NervesHub, but we're already in progress.
    # It could be because the deployment/device was edited making a duplicate
    # update message or a new deployment was created. Either way, lets not
    # interrupt FWUP and let the task finish. After update and reboot, the
    # device will check-in and get an update message if it was actually new and
    # required
    state
  end

  defp maybe_update_firmware(%UpdateInfo{} = update_info, %State{} = state) do
    # Cancel an existing timer if it exists.
    # This prevents rescheduled updates`
    # from compounding.
    state = maybe_cancel_timer(state)

    # possibly offload update decision to an external module.
    # This will allow application developers
    # to control exactly when an update is applied.
    # note: update_available is a behaviour function
    case state.fwup_config.update_available.(update_info) do
      :apply ->
        start_fwup_stream(update_info, state)

      :ignore ->
        state

      {:reschedule, ms} ->
        timer = Process.send_after(self(), {:update_reschedule, update_info}, ms)
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

  @spec start_fwup_stream(UpdateInfo.t(), State.t()) :: State.download_started()
  defp start_fwup_stream(%UpdateInfo{} = update_info, state) do
    pid = self()
    fun = &send(pid, {:download, &1})
    {:ok, download} = Downloader.start_download(update_info.firmware_url, fun)
    {:ok, fwup} = Fwup.stream(pid, fwup_args(state.fwup_config))
    status = {:updating, update_info.firmware_meta.uuid, 0}
    Logger.info("[NervesHubLink] Downloading firmware: #{update_info.firmware_url}")
    %State{state | status: status, download: download, fwup: fwup, update_info: update_info}
  end

  @spec fwup_args(FwupConfig.t()) :: [String.t()]
  defp fwup_args(%FwupConfig{fwup_public_keys: fwup_public_keys, fwup_devpath: devpath}) do
    args = ["--apply", "--no-unmount", "-d", devpath, "--task", "upgrade"]

    Enum.reduce(fwup_public_keys, args, fn public_key, args ->
      args ++ ["--public-key", public_key]
    end)
  end
end
