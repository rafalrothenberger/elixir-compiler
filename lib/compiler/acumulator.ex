defmodule Compiler.Acumulator do
  @moduledoc false

  def start_link() do
    Agent.start_link(fn -> {-1, ""} end, name: :acumulator)
  end

  def set_value(value) do
    Agent.update(:acumulator, fn {_value, var} -> {value, var} end)
  end

  def set_var(var) do
    Agent.update(:acumulator, fn {value, _var} -> {value, var} end)
  end

  def get() do
    Agent.get(:acumulator, fn state -> state end)
  end

  def get_value() do
    Agent.get(:acumulator, fn {value, _var} -> value end)
  end

  def get_var() do
    Agent.get(:acumulator, fn {_value, var} -> var end)
  end

end
