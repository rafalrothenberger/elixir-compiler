defmodule Compiler.Declarations do
  @moduledoc false

  def prepare_variable_map(declarations) do
    for_each_declaration(declarations, %{}, Application.get_env(:compiler, :reserved), [])
  end

  defp for_each_declaration([], variables, address, errors) do
    {variables, address, errors}
  end

  defp for_each_declaration([declaration], variables, address, errors) do
    case declaration do
      {:var, name, line} ->
        if (Map.has_key?(variables, name)) do
          {variables, address, [{:duplicate, {name}, line} | errors]}
        else
          variables = Map.put(variables, name, {:var, 1, address})
          {variables, address+1, errors}
        end
      {:array, name, len, line} ->
        if (Map.has_key?(variables, name)) do
          {variables, address, [{:duplicate, {name}, line} | errors]}
        else
          variables = Map.put(variables, name, {:array, len, address})
          {variables, address+len, errors}
        end
    end
  end

  defp for_each_declaration([declaration | declarations], variables, address, errors) do
    case declaration do
      {:var, name, line} ->
        if (Map.has_key?(variables, name)) do
          {variables, address, [{:duplicate, {name}, line} | errors]}
        else
          variables = Map.put(variables, name, {:var, 1, address})
          for_each_declaration(declarations, variables, address+1, errors)
        end
      {:array, name, len, line} ->
        if (Map.has_key?(variables, name)) do
          {variables, address, [{:duplicate, {name}, line} | errors]}
        else
          variables = Map.put(variables, name, {:array, len, address})
          for_each_declaration(declarations, variables, address+len, errors)
        end
    end
  end
end
