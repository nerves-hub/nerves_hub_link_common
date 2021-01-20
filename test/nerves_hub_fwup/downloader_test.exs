defmodule NervesHubFwup.DownloaderTest do
  use ExUnit.Case

  alias NervesHubFwup.Support.{
    XRetryNumberPlug,
    RedirectPlug,
    RangeRequestPlug,
    HTTPErrorPlug
  }

  alias NervesHubFwup.Downloader

  describe "http error" do
    setup do
      port = 4003

      {:ok, plug} =
        start_supervised({Plug.Cowboy, scheme: :http, plug: HTTPErrorPlug, options: [port: port]})

      {:ok, [plug: plug, url: "http://localhost:#{port}/test"]}
    end

    test "exits when an HTTP error occurs", %{url: url} do
      test_pid = self()
      handler_fun = &send(test_pid, &1)
      Process.flag(:trap_exit, true)
      {:ok, download} = Downloader.start_download(url, handler_fun)
      assert_receive {:error, %Mint.HTTPError{reason: {:http_error, 416}}}
      assert_receive {:EXIT, ^download, {:http_error, 416}}
    end
  end

  describe "range" do
    setup do
      port = 4002

      {:ok, plug} =
        start_supervised(
          {Plug.Cowboy, scheme: :http, plug: RangeRequestPlug, options: [port: port]}
        )

      {:ok, [plug: plug, url: "http://localhost:#{port}/test"]}
    end

    test "calculates range request header", %{url: url} do
      test_pid = self()
      handler_fun = &send(test_pid, &1)
      {:ok, download} = Downloader.start_download(url, handler_fun)

      assert_receive {:data, "h"}
      assert_receive {:error, _}

      :ok = Downloader.resume_download(download)

      refute_receive {:error, _}
      assert_receive {:data, "ello, world"}
    end
  end

  describe "redirect" do
    setup do
      port = 4001

      {:ok, plug} =
        start_supervised({Plug.Cowboy, scheme: :http, plug: RedirectPlug, options: [port: port]})

      {:ok, [plug: plug, url: "http://localhost:#{port}/redirect"]}
    end

    test "follows redirects", %{url: url} do
      test_pid = self()
      handler_fun = &send(test_pid, &1)
      {:ok, _download} = Downloader.start_download(url, handler_fun)
      refute_receive {:error, _}
      assert_receive {:data, "redirected"}
    end
  end

  describe "xretry" do
    setup do
      port = 4000

      {:ok, plug} =
        start_supervised(
          {Plug.Cowboy, scheme: :http, plug: XRetryNumberPlug, options: [port: port]}
        )

      {:ok, [plug: plug, url: "http://localhost:#{port}/test"]}
    end

    test "simple download resume", %{url: url} do
      test_pid = self()
      handler_fun = &send(test_pid, &1)
      expected_data_part_1 = :binary.copy(<<0>>, 2048)
      expected_data_part_2 = :binary.copy(<<1>>, 2048)

      # download the first part of the data.
      # the plug will terminate the connection after 2048 bytes are sent.
      # the handler_fun will send the data to this test's mailbox.
      {:ok, download} = Downloader.start_download(url, handler_fun)
      assert_receive {:data, ^expected_data_part_1}
      assert_receive {:error, _}
      refute_received {:data, ^expected_data_part_2}

      # resume the download.
      # the plug will send the remaining 2048 bytes
      :ok = Downloader.resume_download(download)
      assert_receive {:data, ^expected_data_part_2}

      # the request should complete successfully this time
      assert_receive :complete
    end
  end
end
