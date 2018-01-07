defmodule Compiler.Values do
  @moduledoc false

  def start_link() do
    Agent.start_link(fn -> %{} end, name: :values)
  end

  def set_value(name, value) do
    Agent.update(:values, fn state -> Map.put(state, name, value) end)
  end

  def get_value(name) do
    Agent.get(:values, fn state -> Map.get_lazy(state, name, fn -> -1 end) end)
  end

end
