defmodule NervesHubFwup.Support.HTTPErrorPlug do
  @moduledoc """
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(options), do: options

  @impl Plug
  def call(conn, _opts) do
    conn
    |> send_resp(416, "Range Not Satisfiable")
  end
end
