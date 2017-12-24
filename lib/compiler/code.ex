defmodule Compiler.Code do
  @moduledoc false

  def gen_assembly([], {variables, read_only, address, errors, line_number} = state, assembly) do
    case errors do
      [] -> {:ok, assembly}
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  def gen_assembly([cmd], {variables, read_only, address, errors, line_number} = state, assembly) do
    {code, state} = parse_cmd(cmd, state)
    gen_assembly([], state, "#{assembly}#{code}")
  end

  def gen_assembly([cmd|cmds], {variables, read_only, address, errors, line_number} = state, assembly) do
    {code, state} = parse_cmd(cmd, state)
    gen_assembly(cmds, state, "#{assembly}#{code}")
  end

  defp parse_cmd({line, :assign, {{:var, name}, expression}}, {variables, read_only, address, errors, line_number} = state) do
    cond do
      Map.has_key?(read_only, name) ->
        {"", {variables, read_only, address, [{:assign_read_only, {name}, line} | errors], line_number}}
      Map.has_key?(variables, name) ->
        {type, size, mem_addr} = variables |> Map.get(name)
        if (type == :var) do
          v = parse_expression(expression)
          line_number = line_number + lines(v)
          {"#{v}STORE #{mem_addr}\n", {variables, read_only, address, errors, line_number+1}}
        else
          {"", {variables, read_only, address, [{:accessing_array_as_var, {name}, line} | errors], line_number}}
        end
      true ->
        {"", {variables, read_only, address, [{:var_not_found, {name}, line} | errors], line_number}}
    end
  end

  defp parse_cmd({line, :assign, {{:array, name, :number, i}, expression}}, {variables, read_only, address, errors, line_number} = state) do
    cond do
      Map.has_key?(read_only, name) ->
        {"", {variables, read_only, address, [{:assign_read_only, {name}, line} | errors], line_number}}
      Map.has_key?(variables, name) ->
        {type, size, mem_addr} = variables |> Map.get(name)
        if (type == :array) do
          if (i < size) do
            i = mem_addr+i
            a = parse_number(i)
            a = "#{a}STORE 0\n"
            line_number = line_number+lines(a)+1
            b = parse_expression(expression)
            b = "#{b}STOREI 0\n"
            line_number = line_number+lines(b)+1
            {"#{a}#{b}", {variables, read_only, address, errors, line_number}}
          else
            {"", {variables, read_only, address, [{:out_of_array_range, {name}, line} | errors], line_number}}
          end
        else
          {"", {variables, read_only, address, [{:accessing_var_as_array, {name}, line} | errors], line_number}}
        end
      true ->
        {"", {variables, read_only, address, [{:var_not_found, {name}, line} | errors], line_number}}
    end
  end

  defp parse_cmd({line, :assign, {{:array, name, :var, v}, expression}}, {variables, read_only, address, errors, line_number} = state) do
    cond do
      Map.has_key?(read_only, name) ->
        {"", {variables, read_only, address, [{:assign_read_only, {name}, line} | errors], line_number}}
      Map.has_key?(variables, name) ->
        {type, size, mem_addr} = variables |> Map.get(name)
        if (type == :array) do
          cond do
            Map.has_key?(read_only, v) or Map.has_key?(variables, v) ->
              {v_type, _v_size, v_mem_addr} = Map.get_lazy(read_only, v, fn -> Map.get(variables, v) end)
              a = parse_number(mem_addr)
              a = "#{a}ADD #{v_mem_addr}\nSTORE 0\n"
              line_number = line_number+lines(a)+2
              b = parse_expression(expression)
              b = "#{b}STOREI 0\n"
              line_number = line_number+lines(b)+1
              {"#{a}#{b}", {variables, read_only, address, errors, line_number}}
            true ->
              {"", {variables, read_only, address, [{:var_not_found, {name}, line} | errors], line_number}}
          end
        else
          {"", {variables, read_only, address, [{:accessing_var_as_array, {name}, line} | errors], line_number}}
        end
      true ->
        {"", {variables, read_only, address, [{:var_not_found, {name}, line} | errors], line_number}}
    end
  end

  def lines(s) do
    s |> String.split |> Enum.count
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
