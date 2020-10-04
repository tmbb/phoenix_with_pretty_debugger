defmodule PhoenixWithPrettyDebugger.ConnStorage do
  @moduledoc false
  alias PhoenixWithPrettyDebugger.ConnStorage.Item

  @app_key :phoenix_with_pretty_debugger
  @storage_key :conn_storage

  @doc """
  Sets up the storage map.
  It must be invoked on application start
  """
  def setup() do
    put_storage(%{})
  end

  @doc """
  Puts a `{conn, opts}` pair in storage.
  """
  def put(conn, opts) do
    id = random_id()
    item = Item.new(conn: conn, opts: opts)

    get_storage()
    |> Map.put(id, item)
    |> put_storage()

    id
  end

  @doc """
  Gets a `{conn, opts}` pair from storage.
  """
  def get(id) do
    get_storage()
    |> Map.get(id)
    |> Item.to_pair()
  end

  @doc """
  Pops a `{conn, opts}` pair out of storage.
  The pair is both returned and removed from storage.

  Unlike `Map.pop!/1`, the entire storage is not returned.
  Only the `{conn, opts}` pair is returned.
  This function is destructive on purpose to save memory.
  """
  def pop!(id) do
    {item, new_map} = Map.pop!(get_storage(), id)
    put_storage(new_map)
    Item.to_pair(item)
  end

  defp random_id() do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64()
  end

  defp put_storage(storage) do
    Application.put_env(@app_key, @storage_key, storage)
  end

  defp get_storage() do
    Application.get_env(@app_key, @storage_key)
  end
end