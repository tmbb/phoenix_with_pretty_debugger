defmodule PhoenixWithPrettyDebugger.ConnStorage.Item do
  @moduledoc false

  defstruct conn: nil,
            opts: [],

            timestamp: nil

  @doc """
  Create an `Item` with a `:conn` and `:opts`.
  Will add a creation `:timestamp` to the item.
  """
  def new(options) do
    conn = Keyword.fetch!(options, :conn)
    opts = Keyword.get(options, :opts, [])
    timestamp = DateTime.utc_now()

    %__MODULE__{
      conn: conn,
      opts: opts,
      timestamp: timestamp
    }
  end

  @doc """
  Converts the `Item` into a `{conn, opts}` pair.
  Discards the timestamp.
  """
  def to_pair(%__MODULE__{} = item) do
    {item.conn, item.opts}
  end
end