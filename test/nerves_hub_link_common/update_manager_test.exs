defmodule NervesHubLinkCommon.UpdateManagerTest do
  use ExUnit.Case
  alias NervesHubLinkCommon.Message.{UpdateInfo, FirmwareMetadata}
  alias NervesHubLinkCommon.{FwupConfig, UpdateManager}
  alias NervesHubLinkCommon.Support.FWUPStreamPlug

  describe "fwup stream" do
    setup do
      port = 5000
      devpath = "/tmp/fwup_output"

      update_payload = %UpdateInfo{
        firmware_url: "http://localhost:#{port}/test.fw",
        firmware_meta: %FirmwareMetadata{uuid: "test-uuid"}
      }

      {:ok, plug} =
        start_supervised(
          {Plug.Cowboy, scheme: :http, plug: FWUPStreamPlug, options: [port: port]}
        )

      File.rm(devpath)

      {:ok, [plug: plug, update_payload: update_payload, devpath: "/tmp/fwup_output"]}
    end

    test "apply", %{update_payload: update_payload, devpath: devpath} do
      test_pid = self()
      fwup_fun = &send(test_pid, {:fwup, &1, &2})
      update_available_fun = fn _ -> :apply end

      fwup_config = %FwupConfig{
        fwup_devpath: devpath,
        handle_fwup_message: fwup_fun,
        update_available: update_available_fun
      }

      {:ok, manager} = UpdateManager.start_link(fwup_config)

      assert UpdateManager.apply_update(manager, update_payload) == %UpdateManager.Progress{
               uuid: "test-uuid",
               percent: 0,
               error: nil
             }

      meta = update_payload.firmware_meta

      assert_receive {:fwup, {:progress, 0}, ^meta}
      assert_receive {:fwup, {:progress, 100}, ^meta}
      assert_receive {:fwup, {:ok, 0, ""}, ^meta}
    end

    test "reschedule", %{update_payload: update_payload, devpath: devpath} do
      test_pid = self()
      fwup_fun = &send(test_pid, {:fwup, &1, &2})

      update_available_fun = fn _ ->
        case Process.get(:reschedule) do
          nil ->
            send(test_pid, :rescheduled)
            Process.put(:reschedule, true)
            {:reschedule, 50}

          _ ->
            :apply
        end
      end

      fwup_config = %FwupConfig{
        fwup_devpath: devpath,
        handle_fwup_message: fwup_fun,
        update_available: update_available_fun
      }

      {:ok, manager} = UpdateManager.start_link(fwup_config)
      assert UpdateManager.apply_update(manager, update_payload) == nil
      assert_received :rescheduled
      refute_received {:fwup, _}

      meta = update_payload.firmware_meta

      assert_receive {:fwup, {:progress, 0}, ^meta}
      assert_receive {:fwup, {:progress, 100}, ^meta}
      assert_receive {:fwup, {:ok, 0, ""}, ^meta}
    end
  end
end
