defmodule PhoenixWithPrettyDebugger.Application do
  @moduledoc false
  use Application
  alias PhoenixWithPrettyDebugger.ConnStorage

  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: PhoenixWithPrettyDebugger.TaskSupervisor}
    ]

    ConnStorage.setup()
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end