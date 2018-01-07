defmodule Compiler.Initialized do
  @moduledoc false

  def start_link() do
    Agent.start_link(fn -> %{} end, name: :initialized)
  end

  def initialize(name) do
    Agent.update(:initialized, fn state -> Map.put(state, name, true) end)
  end

  def is_initialized?(name) do
    Agent.get(:initialized, fn state -> Map.get_lazy(state, name, fn -> false end) end)
  end

end
