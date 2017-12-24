defmodule Compiler do

  def run(filename) do
    {:ok, file} = File.open(filename, [:read])
    program = IO.read(file, :all)
#    program = String.replace(program, ~r/\([\s\S]+\)/, "")
#    program = String.replace(program, ~r/[\s\t\n]+/, " ")
#    program = String.trim(program)
    program = String.to_charlist(program)

    a = :compiler_lexer.string(program)
#    IO.inspect(a)

    {:ok, tokens, _} = a
    IO.inspect(tokens)
    {:ok, res} = :compiler_parser.parse(tokens)
#    res = :compiler_parser.parse(tokens)
    IO.inspect(res)
    IO.puts("\n\n\n")
    parse(res)
  end


  defp parse(%{code: code, declarations: declarations}) do
    a = prepare_variable_map(declarations)
    IO.inspect(a)
    {variables, address, errors} = a
  end

  defp prepare_variable_map(declarations) do
    for_each_declaration(declarations, %{}, 0, [])
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
