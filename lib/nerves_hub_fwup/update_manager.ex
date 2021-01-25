defmodule NervesHubFwup.UpdateManager do
  @moduledoc """
  GenServer responsible for brokering messages between:
    * an external controlling process
    * FWUP
    * HTTP

  Should be started in a supervision tree
  """

  require Logger
  use GenServer
  alias NervesHubFwup.{Args, Downloader}

  defmodule State do
    @type status ::
            :idle
            | :fwup_error
            | :update_failed
            | :update_rescheduled
            | {:updating, integer()}
            | :unknown

    @type t :: %__MODULE__{
            status: status(),
            update_reschedule_timer: nil | :timer.tref()
          }

    defstruct status: :idle,
              update_reschedule_timer: nil,
              fwup: nil,
              download: nil,
              args: nil
  end

  @spec apply_update(GenServer.server(), map()) :: State.status()
  def apply_update(manager \\ __MODULE__, %{"firmware_url" => _} = update) do
    GenServer.call(manager, {:apply_update, update})
  end

  def status(manager \\ __MODULE__) do
    GenServer.call(manager, :status)
  end

  @doc "Raises an ArgumentError on invalid arguments"
  def validate_args!(%Args{} = args) do
    args
    |> validate_fwup_public_keys!()
    |> validate_fwup_devpath!()
    |> validate_handle_fwup_message!()
    |> validate_update_available!()
  end

  defp validate_fwup_public_keys!(%Args{fwup_public_keys: list} = args) when is_list(list),
    do: args

  defp validate_fwup_public_keys!(%Args{}),
    do: raise(ArgumentError, message: "invalid arg: fwup_public_keys")

  defp validate_fwup_devpath!(%Args{fwup_devpath: devpath} = args) when is_binary(devpath),
    do: args

  defp validate_fwup_devpath!(%Args{}),
    do: raise(ArgumentError, message: "invalid arg: fwup_devpath")

  defp validate_handle_fwup_message!(%Args{handle_fwup_message: handle_fwup_message} = args)
       when is_function(handle_fwup_message, 1),
       do: args

  defp validate_handle_fwup_message!(%Args{}),
    do: raise(ArgumentError, message: "handle_fwup_message function signature incorrect")

  defp validate_update_available!(%Args{update_available: update_available} = args)
       when is_function(update_available, 1),
       do: args

  defp validate_update_available!(%Args{}),
    do: raise(ArgumentError, message: "update_available function signature incorrect")

  @doc false
  def child_spec(%Args{} = args) do
    %{
      start: {__MODULE__, :start_link, [args, [name: __MODULE__]]},
      id: __MODULE__
    }
  end

  @doc false
  def start_link(%Args{} = args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl GenServer
  def init(%Args{} = args) do
    args = validate_args!(args)
    {:ok, %State{args: args}}
  end

  @impl GenServer
  def handle_call({:apply_update, update}, _from, %State{} = state) do
    state = maybe_update_firmware(update, state)
    {:reply, state.status, state}
  end

  def handle_call(:status, _from, %State{} = state) do
    {:reply, state.status, state}
  end

  @impl GenServer
  def handle_info({:update_reschedule, response}, state) do
    {:noreply, maybe_update_firmware(response, %{state | update_reschedule_timer: nil})}
  end

  # messages from FWUP
  # todo remove fwup from state
  def handle_info({:fwup, {:ok, 0, _message} = full_message}, state) do
    Logger.info("[NervesHubLink] FWUP Finished")
    _ = state.args.handle_fwup_message.(full_message)
    {:noreply, state}
  end

  def handle_info({:fwup, message}, state) do
    _ = state.args.handle_fwup_message.(message)

    case message do
      {:progress, percent} ->
        {:noreply, %{state | status: {:updating, percent}}}

      {:error, _, _message} ->
        {:noreply, %{state | status: :fwup_error}}

      _ ->
        {:noreply, state}
    end
  end

  # Messages from Downloader
  # todo remover downloader from state
  def handle_info({:download, :complete}, state) do
    {:noreply, state}
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

  defp maybe_update_firmware(_data, %{status: {:updating, _percent}} = state) do
    # Received an update message from NervesHub, but we're already in progress.
    # It could be because the deployment/device was edited making a duplicate
    # update message or a new deployment was created. Either way, lets not
    # interrupt FWUP and let the task finish. After update and reboot, the
    # device will check-in and get an update message if it was actually new and
    # required
    state
  end

  defp maybe_update_firmware(%{"firmware_url" => url} = data, state) do
    # Cancel an existing timer if it exists.
    # This prevents rescheduled updates`
    # from compounding.
    state = maybe_cancel_timer(state)

    # possibly offload update decision to an external module.
    # This will allow application developers
    # to control exactly when an update is applied.
    case state.args.update_available.(data) do
      :apply ->
        pid = self()
        fun = &send(pid, {:download, &1})
        {:ok, download} = Downloader.start_download(url, fun)
        {:ok, fwup} = Fwup.stream(pid, fwup_args(state.args))
        Logger.info("[NervesHubLink] Downloading firmware: #{url}")
        %{state | status: {:updating, 0}, download: download, fwup: fwup}

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

  defp fwup_args(%Args{fwup_public_keys: fwup_public_keys, fwup_devpath: devpath}) do
    args = ["--apply", "--no-unmount", "-d", devpath, "--task", "upgrade"]

    Enum.reduce(fwup_public_keys, args, fn public_key, args ->
      args ++ ["--public-key", public_key]
    end)
  end
end
