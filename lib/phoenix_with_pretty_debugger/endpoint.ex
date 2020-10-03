defmodule PhoenixWithPrettyDebugger.Endpoint do
  @moduledoc ~S"""
  Defines a Phoenix endpoint with a prettier debugger
  that supports syntax highlighting.

  The endpoint is the boundary where all requests to your
  web application start. It is also the interface your
  application provides to the underlying web servers.

  The API is exactly the same as the default ´Phoenix.Endpoint`.
  """

  @type topic :: String.t
  @type event :: String.t
  @type msg :: map

  require Logger

  @doc false
  defmacro __using__(opts) do
    quote do
      @behaviour Phoenix.Endpoint

      unquote(config(opts))
      unquote(pubsub())
      unquote(plug())
      unquote(server())
    end
  end

  defp config(opts) do
    quote do
      @otp_app unquote(opts)[:otp_app] || raise "endpoint expects :otp_app to be given"
      var!(config) = Phoenix.Endpoint.Supervisor.config(@otp_app, __MODULE__)
      var!(code_reloading?) = var!(config)[:code_reloader]
      @compile_config Keyword.take(var!(config), Phoenix.Endpoint.Supervisor.compile_config_keys())

      @doc false
      def __compile_config__ do
        @compile_config
      end

      # Avoid unused variable warnings
      _ = var!(code_reloading?)

      @doc false
      def init(_key, config) do
        {:ok, config}
      end

      defoverridable init: 2
    end
  end

  defp pubsub() do
    quote do
      def subscribe(topic, opts \\ []) when is_binary(topic) do
        Phoenix.PubSub.subscribe(pubsub_server!(), topic, opts)
      end

      def unsubscribe(topic) do
        Phoenix.PubSub.unsubscribe(pubsub_server!(), topic)
      end

      def broadcast_from(from, topic, event, msg) do
        Phoenix.Channel.Server.broadcast_from(pubsub_server!(), from, topic, event, msg)
      end

      def broadcast_from!(from, topic, event, msg) do
        Phoenix.Channel.Server.broadcast_from!(pubsub_server!(), from, topic, event, msg)
      end

      def broadcast(topic, event, msg) do
        Phoenix.Channel.Server.broadcast(pubsub_server!(), topic, event, msg)
      end

      def broadcast!(topic, event, msg) do
        Phoenix.Channel.Server.broadcast!(pubsub_server!(), topic, event, msg)
      end

      def local_broadcast(topic, event, msg) do
        Phoenix.Channel.Server.local_broadcast(pubsub_server!(), topic, event, msg)
      end

      def local_broadcast_from(from, topic, event, msg) do
        Phoenix.Channel.Server.local_broadcast_from(pubsub_server!(), from, topic, event, msg)
      end

      defp pubsub_server! do
        config(:pubsub_server) ||
          raise ArgumentError, "no :pubsub_server configured for #{inspect(__MODULE__)}"
      end
    end
  end

  defp plug() do
    quote location: :keep do
      use Plug.Builder, init_mode: Phoenix.plug_init_mode()
      import Phoenix.Endpoint

      Module.register_attribute(__MODULE__, :phoenix_sockets, accumulate: true)

      if force_ssl = Phoenix.Endpoint.__force_ssl__(__MODULE__, var!(config)) do
        plug Plug.SSL, force_ssl
      end

      if var!(config)[:debug_errors] do
        use PhoenixWithPrettyDebugger.Plug.PrettyDebugger,
          otp_app: @otp_app,
          banner: {Phoenix.Endpoint.RenderErrors, :__debugger_banner__, []},
          style: [
            primary: "#EB532D"
          ]
      end

      # Compile after the debugger so we properly wrap it.
      # Yes, we really want to reuse the `Phoenix.Endpoint` @before_compile hook!
      @before_compile Phoenix.Endpoint
    end
  end

  defp server() do
    quote location: :keep, unquote: false do
      @doc """
      Returns the child specification to start the endpoint
      under a supervision tree.
      """
      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :supervisor
        }
      end

      @doc """
      Starts the endpoint supervision tree.
      """
      def start_link(opts \\ []) do
        Phoenix.Endpoint.Supervisor.start_link(@otp_app, __MODULE__, opts)
      end

      @doc """
      Returns the endpoint configuration for `key`

      Returns `default` if the key does not exist.
      """
      def config(key, default \\ nil) do
        case :ets.lookup(__MODULE__, key) do
          [{^key, val}] -> val
          [] -> default
        end
      end

      @doc """
      Reloads the configuration given the application environment changes.
      """
      def config_change(changed, removed) do
        Phoenix.Endpoint.Supervisor.config_change(__MODULE__, changed, removed)
      end

      @doc """
      Generates the endpoint base URL without any path information.

      It uses the configuration under `:url` to generate such.
      """
      def url do
        Phoenix.Config.cache(__MODULE__,
          :__phoenix_url__,
          &Phoenix.Endpoint.Supervisor.url/1)
      end

      @doc """
      Generates the static URL without any path information.

      It uses the configuration under `:static_url` to generate
      such. It falls back to `:url` if `:static_url` is not set.
      """
      def static_url do
        Phoenix.Config.cache(__MODULE__,
          :__phoenix_static_url__,
          &Phoenix.Endpoint.Supervisor.static_url/1)
      end

      @doc """
      Generates the endpoint base URL but as a `URI` struct.

      It uses the configuration under `:url` to generate such.
      Useful for manipulating the URL data and passing it to
      URL helpers.
      """
      def struct_url do
        Phoenix.Config.cache(__MODULE__,
          :__phoenix_struct_url__,
          &Phoenix.Endpoint.Supervisor.struct_url/1)
      end

      @doc """
      Returns the host for the given endpoint.
      """
      def host do
        Phoenix.Config.cache(__MODULE__,
          :__phoenix_host__,
          &Phoenix.Endpoint.Supervisor.host/1)
      end

      @doc """
      Generates the path information when routing to this endpoint.
      """
      def path(path) do
        Phoenix.Config.cache(__MODULE__,
          :__phoenix_path__,
          &Phoenix.Endpoint.Supervisor.path/1) <> path
      end

      @doc """
      Generates the script name.
      """
      def script_name do
        Phoenix.Config.cache(__MODULE__,
          :__phoenix_script_name__,
          &Phoenix.Endpoint.Supervisor.script_name/1)
      end

      @doc """
      Generates a route to a static file in `priv/static`.
      """
      def static_path(path) do
        Phoenix.Config.cache(__MODULE__, :__phoenix_static__,
                             &Phoenix.Endpoint.Supervisor.static_path/1) <>
        elem(static_lookup(path), 0)
      end

      @doc """
      Generates a base64-encoded cryptographic hash (sha512) to a static file
      in `priv/static`. Meant to be used for Subresource Integrity with CDNs.
      """
      def static_integrity(path) do
        elem(static_lookup(path), 1)
      end

      @doc """
      Returns a two item tuple with the first item being the `static_path`
      and the second item being the `static_integrity`.
      """
      def static_lookup(path) do
        Phoenix.Config.cache(__MODULE__, {:__phoenix_static__, path},
                             &Phoenix.Endpoint.Supervisor.static_lookup(&1, path))
      end
    end
  end
end
