defmodule Compiler.Labels do
  @moduledoc false

  def start_link() do
    Agent.start_link(fn -> 0 end, name: :labels)
  end

  def get_label() do
    Agent.get_and_update(:labels, fn i -> {"#LABEL_#{i}", i+1} end)
  end

end
