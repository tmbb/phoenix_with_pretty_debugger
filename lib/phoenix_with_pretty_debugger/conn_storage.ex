defmodule PhoenixWithPrettyDebugger.ConnStorage do
  @moduledoc false

  def setup() do
    Application.put_env(:phoenix_with_pretty_debugger, :conn_storage, %{})
  end

  def put(conn, call_opts) do
    map = Application.get_env(:phoenix_with_pretty_debugger, :conn_storage)
    id = random_id()
    Application.put_env(
      :phoenix_with_pretty_debugger,
      :conn_storage,
      Map.put(map, id, {conn, call_opts})
    )

    id
  end

  def get(id) do
    map = Application.get_env(:phoenix_with_pretty_debugger, :conn_storage)
    Map.get(map, id)
  end

  defp random_id() do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64()
  end
end