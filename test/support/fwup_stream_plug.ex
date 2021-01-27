defmodule NervesHubLinkCommon.Support.FWUPStreamPlug do
  @moduledoc """
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(options), do: options

  @impl Plug
  def call(conn, _opts) do
    {:ok, path} = Fwup.TestSupport.Fixtures.create_firmware("test")

    conn
    |> send_file(200, path)
  end
end
