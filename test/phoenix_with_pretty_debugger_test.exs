defmodule PhoenixWithPrettyDebuggerTest do
  use ExUnit.Case
  doctest PhoenixWithPrettyDebugger

  test "greets the world" do
    assert PhoenixWithPrettyDebugger.hello() == :world
  end
end
