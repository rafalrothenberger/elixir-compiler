defmodule Compiler.Code do
  @moduledoc false

  def gen_assembly([], {variables, read_only, address, errors} = state, assembly) do
    case errors do
      [] -> {:ok, assembly}
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  def gen_assembly([cmd], {variables, read_only, address, errors} = state, assembly) do
    {code, state} = parse_cmd(cmd, state)
    gen_assembly([], state, "#{assembly}#{code}")
  end

  def gen_assembly([cmd|cmds], {variables, read_only, address, errors} = state, assembly) do
    {code, state} = parse_cmd(cmd, state)
    gen_assembly(cmds, state, "#{assembly}#{code}")
  end

  defp parse_cmd({line, :assign, {{:var, name}, expression}}, {variables, read_only, address, errors} = state) do
    if (Map.has_key?(variables, name)) do
      {type, size, mem_addr} = variables |> Map.get(name)
      if (type == :var) do
        {"#{parse_expression(expression)}STORE #{mem_addr}\n", state}
      else
        {"", {variables, read_only, address, [{:accessing_array_as_var, {name}, line} | errors]}}
      end
    else
      {"", {variables, read_only, address, [{:var_not_found, {name}, line} | errors]}}
    end
  end

  def parse_expression({:number, n}) do
    parse_number(n)
  end

  defp parse_number(n) do
    bits = Integer.to_charlist(n,2)
    code = Enum.map(bits, fn bit ->
      case bit do
        49 -> "SHL\nINC\n"
        48 -> "SHL\n"
      end
    end)
    code = Enum.join(code, "")
    code = String.trim_leading(code, "SHL\n")
    "ZERO\n#{code}"
  end

end
