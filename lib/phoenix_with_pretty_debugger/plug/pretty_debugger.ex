defmodule PhoenixWithPrettyDebugger.Plug.PrettyDebugger do
  @moduledoc """
  A module (**not a plug**) for debugging in development.

  The API is compatible with `Phoenix.Debugger`.
  """

  @already_sent {:plug_conn, :sent}

  @logo File.read!("lib/phoenix_with_pretty_debugger/plug/logo.txt")

  @default_style %{
    primary: "#4e2a8e",
    accent: "#607080",
    highlight: "#f0f4fa",
    red_highlight: "#ffe5e5",
    line_color: "#eee",
    text_color: "#203040",
    logo: @logo,
    monospace_font: "menlo, consolas, monospace"
  }

  @debugger_replay_with_breakpoint_key "__debugger_set_breakpoint"

  import Plug.Conn
  require Logger
  alias PhoenixWithPrettyDebugger.Plug.PrettyDebugger.Highlighter
  alias PhoenixWithPrettyDebugger.ConnStorage

  @doc false
  defmacro __using__(opts) do
    quote do
      @plug_debugger unquote(opts)
      @before_compile PhoenixWithPrettyDebugger.Plug.PrettyDebugger
    end
  end

  @doc false
  def maybe_add_breakpoint_and_replay_request(endpoint, conn) do
    case {IEx.started?(), conn.path_info} do
      {true, [@debugger_replay_with_breakpoint_key]} ->
        # extract the conn id and the function we want to trace
        conn = Plug.Conn.fetch_query_params(conn)
        conn_id = conn.query_params["id"]
        encoded_mfa = conn.query_params["mfa"]
        {m, f, a} = decode_data(encoded_mfa)
        # Insert breakpoint
        IEx.break!(m, f, a)
        # Get the old connection and options from storage
        {old_conn, old_opts} = ConnStorage.pop!(conn_id)
        # Create a response
        response_text = """
          Breakpoint entered.
          You can now pry it on your IEx session.
          """
        # Send the response back to the client
        send_resp(conn, 200, response_text)
        # Replay the original request.
        # I'm still not sure how this works.
        endpoint.call(old_conn, old_opts)

      _ ->
        nil
    end
  end

  defp encode_data(data) do
    data
    |> :erlang.term_to_binary()
    |> Base.url_encode64()
  end

  defp decode_data(binary) do
    binary
    |> Base.url_decode64!()
    |> :erlang.binary_to_term()
  end

  defp url_for_replaying_with_breakpoint(conn_id, mfa) do
    encoded_mfa = encode_data(mfa)
    "/#{@debugger_replay_with_breakpoint_key}?id=#{conn_id}&amp;mfa=#{encoded_mfa}"
  end

  @doc false
  defmacro __before_compile__(_) do
    quote location: :keep do
      # Allows we to override the default `MyAppWeb.Endpoint.call/2` function,
      # while storing it for use later (using `super/2`)
      defoverridable call: 2

      # The function that will override the `MyAppWeb.Endpoint.call/2`
      def call(conn, opts) do
        try do
          PhoenixWithPrettyDebugger.Plug.PrettyDebugger.maybe_add_breakpoint_and_replay_request(
            __MODULE__,
            conn
          )

          # Try to run the default call if available
          super(conn, opts)
        rescue
          e in Plug.Conn.WrapperError ->
            %{conn: conn, kind: kind, reason: reason, stack: stack} = e
            PhoenixWithPrettyDebugger.Plug.PrettyDebugger.__catch__(conn, kind, reason, stack, @plug_debugger, opts)
        catch
          kind, reason ->
            PhoenixWithPrettyDebugger.Plug.PrettyDebugger.__catch__(conn, kind, reason, System.stacktrace(), @plug_debugger, opts)
        end
      end
    end
  end

  @doc false
  def __catch__(conn, kind, reason, stack, opts, call_opts) do
    reason = Exception.normalize(kind, reason, stack)
    status = status(kind, reason)

    receive do
      @already_sent ->
        send(self(), @already_sent)
        log(status, kind, reason, stack)
        :erlang.raise(kind, reason, stack)
    after
      0 ->
        render(conn, status, kind, reason, stack, opts, call_opts)
        log(status, kind, reason, stack)
        :erlang.raise(kind, reason, stack)
    end
  end

  # We don't log status >= 500 because those are treated as errors and logged later.
  defp log(status, kind, reason, stack) when status < 500,
    do: Logger.debug(Exception.format(kind, reason, stack))

  defp log(_status, _kind, _reason, _stack), do: :ok

  ## Rendering

  require EEx

  html_template_path = "lib/phoenix_with_pretty_debugger/plug/pretty_debugger/templates/debugger.html.eex"
  markdown_template_path = "lib/phoenix_with_pretty_debugger/plug/pretty_debugger/templates/debugger.md.eex"
  normalize_css_path = "lib/phoenix_with_pretty_debugger/plug/pretty_debugger/assets/normalize.css"
  style_css_path = "lib/phoenix_with_pretty_debugger/plug/pretty_debugger/assets/style.css"

  @external_resource normalize_css_path
  @external_resource style_css_path
  @external_resource html_template_path
  @external_resource markdown_template_path

  EEx.function_from_file(:defp, :template_html, html_template_path, [:assigns])

  EEx.function_from_file(:defp, :template_markdown, markdown_template_path, [:assigns])

  EEx.function_from_file(:defp, :normalize_css, normalize_css_path, [:_assigns])

  EEx.function_from_file(:defp, :style_css, style_css_path, [:assigns])

  # Made public with @doc false for testing.
  @doc false
  def render(conn, status, kind, reason, stack, opts, call_opts) do
    session = maybe_fetch_session(conn)
    params = maybe_fetch_query_params(conn)
    {title, message} = info(kind, reason)
    style = Enum.into(opts[:style] || [], @default_style)
    banner = banner(conn, status, kind, reason, stack, opts)
    conn_id = ConnStorage.put(conn, call_opts)

    if accepts_html?(get_req_header(conn, "accept")) do
      conn = put_resp_content_type(conn, "text/html")

      assigns = [
        conn: conn,
        conn_id: conn_id,
        frames: frames(stack, opts),
        title: title,
        message: message,
        session: session,
        params: params,
        style: style,
        banner: banner
      ]

      send_resp(conn, status, template_html(assigns))
    else
      # TODO: Remove exported check once we depend on Elixir v1.5 only
      {reason, stack} =
        if function_exported?(Exception, :blame, 3) do
          apply(Exception, :blame, [kind, reason, stack])
        else
          {reason, stack}
        end

      conn = put_resp_content_type(conn, "text/markdown")

      assigns = [
        conn: conn,
        conn_id: conn_id,
        title: title,
        formatted: Exception.format(kind, reason, stack),
        session: session,
        params: params
      ]

      send_resp(conn, status, template_markdown(assigns))
    end
  end

  defp accepts_html?(_accept_header = []), do: false

  defp accepts_html?(_accept_header = [header | _]),
    do: String.contains?(header, ["*/*", "text/*", "text/html"])

  defp maybe_fetch_session(conn) do
    if conn.private[:plug_session_fetch] do
      fetch_session(conn).private[:plug_session]
    end
  end

  defp maybe_fetch_query_params(conn) do
    fetch_query_params(conn).params
  rescue
    Plug.Conn.InvalidQueryError ->
      case conn.params do
        %Plug.Conn.Unfetched{} -> %{}
        params -> params
      end
  end

  defp status(:error, error), do: Plug.Exception.status(error)
  defp status(_, _), do: 500

  defp info(:error, error), do: {inspect(error.__struct__), Exception.message(error)}
  defp info(:throw, thrown), do: {"unhandled throw", inspect(thrown)}
  defp info(:exit, reason), do: {"unhandled exit", Exception.format_exit(reason)}

  defp frames(stacktrace, opts) do
    app = opts[:otp_app]
    editor = System.get_env("PLUG_EDITOR")

    stacktrace
    |> Enum.map_reduce(0, &each_frame(&1, &2, app, editor))
    |> elem(0)
  end

  defp each_frame(entry, index, root, editor) do
    {module, info, location, app, fun, arity, args} = get_entry(entry)
    {file, line} = {to_string(location[:file] || "nofile"), location[:line]}

    doc = module && get_doc(module, fun, arity, app)
    clauses = module && get_clauses(module, fun, args)
    source = get_source(module, file)
    context = get_context(root, app)
    snippet = Highlighter.get_snippet(source, line)
    # We don't need the filename to highlight the arguments
    highlighted_args = Highlighter.highlight_args(args)

    # It's possible that the `snippet` and the `args` won't be highlighted.
    # This can happen, for example, because a supported lexer isn't available.
    # In that case, we render them without syntax highlighting.
    # Even if they are not highlighted, they are escaped by the `Highlighter` module,
    # so that they can be added to the template whether they have been highlighted or not.

    {%{
       app: app,
       info: info,
       file: file,
       line: line,
       context: context,
       snippet: snippet,
       index: index,
       doc: doc,
       clauses: clauses,
       args: highlighted_args,
       mfa: {module, fun, arity},
       link: editor && get_editor(source, line, editor)
     }, index + 1}
  end

  # From :elixir_compiler_*
  defp get_entry({module, :__MODULE__, 0, location}) do
    {module, inspect(module) <> " (module)", location, get_app(module), nil, nil, nil}
  end

  # From :elixir_compiler_*
  defp get_entry({_module, :__MODULE__, 1, location}) do
    {nil, "(module)", location, nil, nil, nil, nil}
  end

  # From :elixir_compiler_*
  defp get_entry({_module, :__FILE__, 1, location}) do
    {nil, "(file)", location, nil, nil, nil, nil}
  end

  defp get_entry({module, fun, args, location}) when is_list(args) do
    arity = length(args)
    formatted_mfa = Exception.format_mfa(module, fun, arity)
    {module, formatted_mfa, location, get_app(module), fun, arity, args}
  end

  defp get_entry({module, fun, arity, location}) do
    {module, Exception.format_mfa(module, fun, arity), location, get_app(module), fun, arity, nil}
  end

  defp get_entry({fun, arity, location}) do
    {nil, Exception.format_fa(fun, arity), location, nil, fun, arity, nil}
  end

  defp get_app(module) do
    case :application.get_application(module) do
      {:ok, app} -> app
      :undefined -> nil
    end
  end

  defp get_doc(module, fun, arity, app) do
    with true <- has_docs?(module, fun, arity),
         {:ok, vsn} <- :application.get_key(app, :vsn) do
      vsn = vsn |> List.to_string() |> String.split("-") |> hd()
      fun = fun |> Atom.to_string() |> URI.encode()
      "https://hexdocs.pm/#{app}/#{vsn}/#{inspect(module)}.html##{fun}/#{arity}"
    else
      _ -> nil
    end
  end

  # TODO: Remove exported check once we depend on Elixir v1.7+
  if Code.ensure_loaded?(Code) and function_exported?(Code, :fetch_docs, 1) do
    def has_docs?(module, name, arity) do
      case Code.fetch_docs(module) do
        {:docs_v1, _, _, _, module_doc, _, docs} when module_doc != :hidden ->
          Enum.any?(docs, has_doc_matcher?(name, arity))

        _ ->
          false
      end
    end

    defp has_doc_matcher?(name, arity) do
      &match?(
        {{kind, ^name, ^arity}, _, _, doc, _}
        when kind in [:function, :macro] and doc != :hidden,
        &1
      )
    end
  else
    def has_docs?(module, fun, arity) do
      docs = Code.get_docs(module, :docs)
      not is_nil(docs) and List.keymember?(docs, {fun, arity}, 0)
    end
  end

  defp get_clauses(module, fun, args) do
    # TODO: Remove exported check once we depend on Elixir v1.5 only
    with true <- is_list(args) and function_exported?(Exception, :blame_mfa, 3),
         {:ok, kind, clauses} <- apply(Exception, :blame_mfa, [module, fun, args]) do
      top_10 =
        clauses
        |> Enum.take(10)
        |> Enum.map(fn {args, guards} ->
          code = Enum.reduce(guards, {fun, [], args}, &{:when, [], [&2, &1]})
          "#{kind} " <> Macro.to_string(code, &clause_match/2)
        end)

      {length(top_10), length(clauses), top_10}
    else
      _ -> nil
    end
  end

  defp clause_match(%{match?: true, node: node}, _),
    do: ~s(<i class="green">) <> h(Macro.to_string(node)) <> "</i>"

  defp clause_match(%{match?: false, node: node}, _),
    do: ~s(<i class="red">) <> h(Macro.to_string(node)) <> "</i>"

  defp clause_match(_, string), do: string

  defp get_context(app, app) when app != nil, do: :app
  defp get_context(_app1, _app2), do: :all

  defp get_source(module, file) do
    cond do
      File.regular?(file) ->
        file

      source = module && Code.ensure_loaded?(module) && module.module_info(:compile)[:source] ->
        to_string(source)

      true ->
        file
    end
  end

  defp get_editor(file, line, editor) do
    editor
    |> :binary.replace("__FILE__", URI.encode(Path.expand(file)))
    |> :binary.replace("__LINE__", to_string(line))
    |> h
  end

  defp banner(conn, status, kind, reason, stack, opts) do
    case Keyword.fetch(opts, :banner) do
      {:ok, {mod, func, args}} ->
        apply(mod, func, [conn, status, kind, reason, stack] ++ args)

      {:ok, other} ->
        raise ArgumentError,
              "expected :banner to be an MFA ({module, func, args}), got: #{inspect(other)}"

      :error ->
        nil
    end
  end

  ## Helpers

  defp method(%Plug.Conn{method: method}), do: method

  defp url(%Plug.Conn{scheme: scheme, host: host, port: port} = conn),
    do: "#{scheme}://#{host}:#{port}#{conn.request_path}"

  defp h(string) do
    string |> to_string() |> Plug.HTML.html_escape()
  end
end
