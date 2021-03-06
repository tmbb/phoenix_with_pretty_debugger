defmodule PhoenixWithPrettyDebugger.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_with_pretty_debugger,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {PhoenixWithPrettyDebugger.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix, "~> 1.4"},
      {:makeup_erlang, "~> 0.1.0"},
      {:makeup_elixir, "~> 0.15"}
    ]
  end
end
