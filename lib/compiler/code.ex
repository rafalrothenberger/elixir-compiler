defmodule Compiler.Code do
  @moduledoc false

  def gen_assembly([], {variables, read_only, address, errors, line_number} = state, assembly) do
    case errors do
      [] -> {:ok, assembly}
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  def gen_assembly([cmd], {variables, read_only, address, errors, line_number} = state, assembly) do
    {code, {variables, read_only, address, errors, _line_number}} = parse_cmd(cmd, state)
    gen_assembly([], {variables, read_only, address, errors, line_number + lines(code)}, "#{assembly}#{code}")
  end

  def gen_assembly([cmd|cmds], {variables, read_only, address, errors, line_number} = state, assembly) do
    {code, {variables, read_only, address, errors, _line_number}} = parse_cmd(cmd, state)
    gen_assembly(cmds, {variables, read_only, address, errors, line_number + lines(code)}, "#{assembly}#{code}")
  end

  defp parse_cmd({line, :assign, {{type, name, _ops} = target, expression}}, {variables, read_only, address, errors, line_number} = state) do
    cond do
      Map.has_key?(read_only, name) ->
        {"", {variables, read_only, address, [{:assign_read_only, {name}, line} | errors], line_number}}
      Map.has_key?(variables, name) ->
        var = Map.get(variables, name)
        {var_type, _var_size, _var_mem_addr} = var
        if (var_type == type) do
          {assembly, state} = parse_expression(expression, state, line)
          assign({target, var}, assembly, state, line)
        else
          case var_type do
            :array -> {"", {variables, read_only, address, [{:accessing_array_as_var, {name}, line} | errors], line_number}}
            :var -> {"", {variables, read_only, address, [{:accessing_var_as_array, {name}, line} | errors], line_number}}
          end
        end
      true ->
        {"", {variables, read_only, address, [{:var_not_found, {name}, line} | errors], line_number}}
    end
  end

  defp assign({{:var, _name, {}}, {_type, _size, mem_addr}}, expression_code, state, _line) do
    {"#{expression_code}STORE #{mem_addr}\n", state}
  end

  defp assign({{:array, _name, {:number, _i}}, {_type, _size, _mem_addr}} = var, expression_code, {variables, read_only, address, errors, line_number} = state, line) do
    {assembly, state} = calc_arr_mem_addr(var, state, line)
    {"#{assembly}STORE 0\n#{expression_code}STOREI 0\n",state}
  end

  defp assign({{:array, _name, {:var, _v}}, {_type, _size, _mem_addr}} = var, expression_code, {variables, read_only, address, errors, line_number} = state, line) do
    {assembly, state} = calc_arr_mem_addr(var, state, line)
    {"#{assembly}STORE 0\n#{expression_code}STOREI 0\n",state}
  end

  def parse_expression({:number, {n}}, {variables, read_only, address, errors, line_number}, line) do
    assembly = parse_number(n)
    {assembly, {variables, read_only, address, errors, line_number}}
  end

  def parse_expression({:var, _name, {}} = var, {_variables, _read_only, _address, _errors, _line_number} = state, line) do
    {mem_addr, state} = get_mem_addr(var, state, line)
    {"LOAD #{mem_addr}\n", state}
  end

  def parse_expression({:array, _name, _ops} = var, {variables, read_only, address, errors, line_number} = state, line) do
    {assembly, state} = get_arr_mem_addr(var, state, line)
    {"#{assembly}\nSTORE 1\nLOADI 1\n", state}
  end

  def parse_expression({:add, {:number, a}, {:number, b}}, {variables, read_only, address, errors, line_number}, line) do
    assembly = parse_number(a+b)
    {assembly, {variables, read_only, address, errors, line_number+lines(assembly)}}
  end

  def parse_expression({:add, {:var, name}, {:number, n}}, {variables, read_only, address, errors, line_number}, line) do
    cond do
      Map.has_key?(read_only, name) or Map.has_key?(variables, name) ->
        {type, _size, mem_addr} = Map.get_lazy(read_only, name, fn -> Map.get(variables, name) end)
        if (type == :var) do

          number = parse_number(n)
          line_number = line_number + lines(number)

          {"ADD #{mem_addr}\n", {variables, read_only, address, errors, line_number+1}}
        else
          {"", {variables, read_only, address, [{:accessing_array_as_var, {name}, line} | errors], line_number}}
        end
      true ->
        {"", {variables, read_only, address, [{:var_not_found, {name}, line} | errors], line_number}}
    end
  end

  def parse_expression({:add, {:number, n}, {:var, name}}, {variables, read_only, address, errors, line_number}, line) do
    parse_expression({:add, {:var, name}, {:number, n}}, {variables, read_only, address, errors, line_number}, line)
  end

  def parse_expression({:add, {:var, left}, {:var, right}}, {variables, read_only, address, errors, line_number}, line) do
    cond do
      Map.has_key?(read_only, left) or Map.has_key?(variables, left) ->
        {type, _size, mem_addr_left} = Map.get_lazy(read_only, left, fn -> Map.get(variables, left) end)
        if (type == :var) do
          cond do
            Map.has_key?(read_only, right) or Map.has_key?(variables, right) ->
              {type, _size, mem_addr_right} = Map.get_lazy(read_only, right, fn -> Map.get(variables, right) end)
              if (type == :var) do

                {"LOAD #{mem_addr_left}\nADD #{mem_addr_right}\n", {variables, read_only, address, errors, line_number+2}}
              else
                {"", {variables, read_only, address, [{:accessing_array_as_var, {right}, line} | errors], line_number}}
              end
            true ->
              {"", {variables, read_only, address, [{:var_not_found, {right}, line} | errors], line_number}}
          end
        else
          {"", {variables, read_only, address, [{:accessing_array_as_var, {left}, line} | errors], line_number}}
        end
      true ->
        {"", {variables, read_only, address, [{:var_not_found, {left}, line} | errors], line_number}}
    end
  end

  defp calc_arr_mem_addr({{:array, name, {:number, i}}, {_type, size, mem_addr}}, {variables, read_only, address, errors, line_number} = state, line) do
    if (i < size) do
      i = i+mem_addr
      assembly = parse_number(i)
      {"#{assembly}", {variables, read_only, address, errors, line_number}}
    else
      {"", {variables, read_only, address, [{:out_of_array_range, {name}, line} | errors], line_number}}
    end
  end

  defp calc_arr_mem_addr({{:array, name, {:var, var_name}}, {_type, size, mem_addr}}, {variables, read_only, address, errors, line_number} = state, line) do
    assembly = parse_number(mem_addr)
    {mem_addr, state} = get_mem_addr({:var, var_name, {}}, state, line)
    {"#{assembly}ADD #{mem_addr}\n",state}
  end

  defp get_arr_mem_addr({:array, name, _ops} = var, {variables, read_only, address, errors, line_number} = state, line) do
    cond do
      Map.has_key?(read_only, name) or Map.has_key?(variables, name) ->
        arr = Map.get_lazy(read_only, name, fn -> Map.get(variables, name) end)
        {type, _size, _mem_addr} = arr
        if (type == :array) do
          calc_arr_mem_addr({var, arr}, state, line)
        else
          {"", {variables, read_only, address, [{:accessing_array_as_var, {name}, line} | errors], line_number}}
        end
      true ->
        {"", {variables, read_only, address, [{:var_not_found, {name}, line} | errors], line_number}}
    end
  end

  defp get_mem_addr({:var, name, {}}, {variables, read_only, address, errors, line_number} = state, line) do
    cond do
      Map.has_key?(read_only, name) or Map.has_key?(variables, name) ->
        {type, _size, mem_addr} = Map.get_lazy(read_only, name, fn -> Map.get(variables, name) end)
        if (type == :var) do
          {mem_addr, {variables, read_only, address, errors, line_number}}
        else
          {"", {variables, read_only, address, [{:accessing_array_as_var, {name}, line} | errors], line_number}}
        end
      true ->
        {"", {variables, read_only, address, [{:var_not_found, {name}, line} | errors], line_number}}
    end
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

  def lines(s) do
    s |> String.split |> Enum.count
  end

end
