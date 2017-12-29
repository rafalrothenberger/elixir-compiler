defmodule Compiler.Code do
  @moduledoc false
  alias Compiler.Labels, as: Labels

  def gen_assembly([], {variables, read_only, address, errors} = state, assembly) do
    case errors do
      [] -> {:ok, assembly, errors}
      _ -> {:error, "", errors}
    end
  end

  def gen_assembly([cmd], {variables, read_only, address, errors} = state, assembly) do
    {code, {variables, read_only, address, errors}} = parse_cmd(cmd, state)
    gen_assembly([], {variables, read_only, address, errors}, "#{assembly}#{code}")
  end

  def gen_assembly([cmd|cmds], {variables, read_only, address, errors} = state, assembly) do
    {code, {variables, read_only, address, errors}} = parse_cmd(cmd, state)
    gen_assembly(cmds, {variables, read_only, address, errors}, "#{assembly}#{code}")
  end

  defp parse_cmd({line, :assign, {{type, name, _ops} = target, expression}}, {variables, read_only, address, errors} = state) do
    cond do
      Map.has_key?(read_only, name) ->
        {"", {variables, read_only, address, [{:assign_read_only, {name}, line} | errors]}}
      Map.has_key?(variables, name) ->
        var = Map.get(variables, name)
        {var_type, _var_size, _var_mem_addr} = var
        if (var_type == type) do
#          {assembly, state} = parse_expression(expression, state, line)
          assign({target, var}, expression, state, line)
        else
          case var_type do
            :array -> {"", {variables, read_only, address, [{:accessing_array_as_var, {name}, line} | errors]}}
            :var -> {"", {variables, read_only, address, [{:accessing_var_as_array, {name}, line} | errors]}}
          end
        end
      true ->
        {"", {variables, read_only, address, [{:var_not_found, {name}, line} | errors]}}
    end
  end

  defp parse_cmd({line, :read, {{type, name, _ops} = target}}, {variables, read_only, address, errors} = state) do
    cond do
      Map.has_key?(read_only, name) ->
        {"", {variables, read_only, address, [{:assign_read_only, {name}, line} | errors]}}
      Map.has_key?(variables, name) ->
        var = Map.get(variables, name)
        {var_type, _var_size, _var_mem_addr} = var
        if (var_type == type) do
          assign({target, var}, "GET\n", state, line)
        else
          case var_type do
            :array -> {"", {variables, read_only, address, [{:accessing_array_as_var, {name}, line} | errors]}}
            :var -> {"", {variables, read_only, address, [{:accessing_var_as_array, {name}, line} | errors]}}
          end
        end
      true ->
        {"", {variables, read_only, address, [{:var_not_found, {name}, line} | errors]}}
    end
  end

  defp parse_cmd({line, :write, {{:number, {n}}}}, {variables, read_only, address, errors} = state) do
    {"#{parse_number(n)}PUT\n", state}
  end

  defp parse_cmd({line, :write, {{type, name, _ops} = target}}, {variables, read_only, address, errors} = state) do
    cond do
      Map.has_key?(read_only, name) ->
        {"", {variables, read_only, address, [{:assign_read_only, {name}, line} | errors]}}
      Map.has_key?(variables, name) ->
        var = Map.get(variables, name)
        {var_type, _var_size, _var_mem_addr} = var
        if (var_type == type) do
          put({target, var}, state, line)
        else
          case var_type do
            :array -> {"", {variables, read_only, address, [{:accessing_array_as_var, {name}, line} | errors]}}
            :var -> {"", {variables, read_only, address, [{:accessing_var_as_array, {name}, line} | errors]}}
          end
        end
      true ->
        {"", {variables, read_only, address, [{:var_not_found, {name}, line} | errors]}}
    end
  end

  defp parse_cmd({line, :ifonly, {condition, cmds}}, {variables, read_only, address, errors} = state) do
    parse_condition({condition, cmds}, state, line)
  end

  defp parse_condition({{:equals, {:number, {a}}, {:number, {b}}}, cmds}, {variables, read_only, address, errors} = state, line) do
    if (a == b) do
      {_, assembly, errors} = gen_assembly(cmds, state, "")
      {assembly, {variables, read_only, address, errors}}
    else
      {"", {variables, read_only, address, errors}}
    end
  end

  defp parse_condition({{:equals, {:number, {n}}, {:var, name, {}} = var}, cmds}, {variables, read_only, address, errors} = state, line) do
    parse_condition({{:equals, var, {:number, {n}}}, cmds}, state, line)
  end

  defp parse_condition({{:equals, {:var, name, {}} = var, value}, cmds}, {variables, read_only, address, errors} = state, line) do
    {value_code, state} = parse_expression(value, state, line)
    {mem_addr, state} = get_mem_addr(var, state, line)
    skip = Labels.get_label()
    start = Labels.get_label()
    code = "#{value_code}INC\nSUB #{mem_addr}\nJZERO #{skip}\nDEC\nJZERO #{start}\nJUMP #{skip}\n!#{start}!"
    {_, assembly, errors} = gen_assembly(cmds, state, "")
    {"#{code}#{assembly}!#{skip}!", {variables, read_only, address, errors}}
  end

  defp parse_condition({{:equals, {:array, name, _ops} = var, value}, cmds}, {variables, read_only, address, errors} = state, line) do
    {value_code, state} = parse_expression(value, state, line)
    {array_code, state} = get_arr_mem_addr(var, state, line)
    skip = Labels.get_label()
    start = Labels.get_label()
    code = "#{array_code}STORE 1\n#{value_code}INC\nSUBI 1\nJZERO #{skip}\nDEC\nJZERO #{start}\nJUMP #{skip}\n!#{start}!"
    {_, assembly, errors} = gen_assembly(cmds, state, "")
    {"#{code}#{assembly}!#{skip}!", {variables, read_only, address, errors}}
  end

  defp parse_condition({{:ne, {:number, {a}}, {:number, {b}}}, cmds}, {variables, read_only, address, errors} = state, line) do
    if (a != b) do
      {_, assembly, errors} = gen_assembly(cmds, state, "")
      {assembly, {variables, read_only, address, errors}}
    else
      {"", {variables, read_only, address, errors}}
    end
  end

  defp parse_condition({{:ne, {:number, {n}}, {:var, name, {}} = var}, cmds}, {variables, read_only, address, errors} = state, line) do
    parse_condition({{:ne, var, {:number, {n}}}, cmds}, state, line)
  end

  defp parse_condition({{:ne, {:var, name, {}} = var, value}, cmds}, {variables, read_only, address, errors} = state, line) do
    {value_code, state} = parse_expression(value, state, line)
    {mem_addr, state} = get_mem_addr(var, state, line)
    skip = Labels.get_label()
    start = Labels.get_label()
    code = "#{value_code}INC\nSUB #{mem_addr}\nJZERO #{start}\nDEC\nJZERO #{skip}\n!#{start}!"
    {_, assembly, errors} = gen_assembly(cmds, state, "")
    {"#{code}#{assembly}!#{skip}!", {variables, read_only, address, errors}}
  end

  defp parse_condition({{:ne, {:array, name, _ops} = var, value}, cmds}, {variables, read_only, address, errors} = state, line) do
    {value_code, state} = parse_expression(value, state, line)
    {array_code, state} = get_arr_mem_addr(var, state, line)
    skip = Labels.get_label()
    start = Labels.get_label()
    code = "#{array_code}STORE 1\n#{value_code}INC\nSUBI 1\nJZERO #{start}\nDEC\nJZERO #{skip}\n!#{start}!"
    {_, assembly, errors} = gen_assembly(cmds, state, "")
    {"#{code}#{assembly}!#{skip}!", {variables, read_only, address, errors}}
  end

  defp put({{:var, _name, {}}, {_type, _size, mem_addr}}, state, _line) do
    {"LOAD #{mem_addr}\nPUT\n", state}
  end

  defp put({{:array, _name, _ops}, {_type, _size, _mem_addr}} = var, {variables, read_only, address, errors} = state, line) do
    {assembly, state} = calc_arr_mem_addr(var, state, line)
    {"#{assembly}STORE 0\nLOADI 0\nPUT\n",state}
  end

  defp assign({{:var, _name, {}}, {_type, _size, mem_addr}}, expression, state, line) do
    {expression_code, {variables, read_only, address, errors}} = parse_expression(expression, state, line)
    {"#{expression_code}STORE #{mem_addr}\n", {variables, read_only, address, errors}}
  end

  defp assign({{:array, _name, _ops}, {_type, _size, _mem_addr}} = var, expression, {variables, read_only, address, errors} = state, line) do
    {assembly, state} = calc_arr_mem_addr(var, state, line)
    {expression_code, {variables, read_only, address, errors}} = parse_expression(expression, state, line)
    {"#{assembly}STORE 0\n#{expression_code}STOREI 0\n",{variables, read_only, address, errors}}
  end

#  defp assign({{:array, _name, {:var, _v}}, {_type, _size, _mem_addr}} = var, expression, {variables, read_only, address, errors} = state, line) do
#    {assembly, state} = calc_arr_mem_addr(var, state, line)
#    {"#{assembly}STORE 0\n#{expression_code}STOREI 0\n",state}
#  end

  def parse_expression(code, {variables, read_only, address, errors}, line) when is_binary(code) do
    {code, {variables, read_only, address, errors}}
  end

  def parse_expression({:number, {n}}, {variables, read_only, address, errors}, line) do
    assembly = parse_number(n)
    {assembly, {variables, read_only, address, errors}}
  end

  def parse_expression({:var, _name, {}} = var, {variables, read_only, address, errors} = state, line) do
    {mem_addr, state} = get_mem_addr(var, state, line)
    {"LOAD #{mem_addr}\n", {variables, read_only, address, errors}}
  end

  def parse_expression({:array, _name, _ops} = var, {variables, read_only, address, errors} = state, line) do
    {assembly, state} = get_arr_mem_addr(var, state, line)
    {"#{assembly}STORE 1\nLOADI 1\n", {variables, read_only, address, errors}}
  end

  def parse_expression({:add, {:number, {a}}, {:number, {b}}}, {variables, read_only, address, errors} = state, line) do
    assembly = parse_number(a+b)
    {assembly, {variables, read_only, address, errors}}
  end

  def parse_expression({:add, {:number, {n}}, expression}, {variables, read_only, address, errors}, line) do
    parse_expression({:add, expression, {:number, {n}}}, {variables, read_only, address, errors}, line)
  end

  def parse_expression({:add, {:var, name, {}} = var, expression}, {variables, read_only, address, errors} = state, line) do
    {mem_addr, state} = get_mem_addr(var, state, line)
    {expression_code, {variables, read_only, address, errors}} = parse_expression(expression, state, line)
    {"#{expression_code}ADD #{mem_addr}\n",{variables, read_only, address, errors}}
  end

  def parse_expression({:add, {:array, name, _ops} = var, expression}, {variables, read_only, address, errors} = state, line) do
    {array_code, state} = get_arr_mem_addr(var, state, line)
    {expression_code, {variables, read_only, address, errors}} = parse_expression(expression, state, line)
    {"#{array_code}STORE 2\n#{expression_code}ADDI 2\n", {variables, read_only, address, errors}}
  end

  def parse_expression({:sub, {:number, {a}}, {:number, {b}}}, {variables, read_only, address, errors} = state, line) do
    assembly = parse_number(max(a-b, 0))
    {assembly, {variables, read_only, address, errors}}
  end

  def parse_expression({:sub, expression, {:number, {n}}}, {variables, read_only, address, errors} = state, line) do
    #parse_expression({:sub, {:number, {n}}, expression}, {variables, read_only, address, errors}, line)
    number_assembly = parse_number(n)
    {expression_code, {variables, read_only, address, errors}} = parse_expression(expression, state, line)
    {"#{number_assembly}STORE 9\n#{expression_code}SUB 9\n",{variables, read_only, address, errors}}
  end

  def parse_expression({:sub, expression, {:var, name, {}} = var}, {variables, read_only, address, errors} = state, line) do
    {mem_addr, state} = get_mem_addr(var, state, line)
    {expression_code, {variables, read_only, address, errors}} = parse_expression(expression, state, line)
    {"#{expression_code}SUB #{mem_addr}\n",{variables, read_only, address, errors}}
  end

  def parse_expression({:sub, expression, {:array, name, _ops} = var}, {variables, read_only, address, errors} = state, line) do
    {array_code, state} = get_arr_mem_addr(var, state, line)
    {expression_code, {variables, read_only, address, errors}} = parse_expression(expression, state, line)
    {"#{array_code}STORE 2\n#{expression_code}SUBI 2\n", {variables, read_only, address, errors}}
  end

  def parse_expression({:multiply, {:number, {a}}, {:number, {b}}}, {variables, read_only, address, errors} = state, line) do
    assembly = parse_number(a*b)
    {assembly, {variables, read_only, address, errors}}
  end

  def parse_expression({:multiply, expression, {:number, {n}}}, {variables, read_only, address, errors} = state, line) do
    parse_expression({:multiply, {:number, {n}}, expression}, {variables, read_only, address, errors}, line)
  end

  def parse_expression({:multiply, {:number, {n}}, {:var, name, {}} = var}, {variables, read_only, address, errors} = state, line) do
    {mem_addr, {variables, read_only, address, errors}} = get_mem_addr(var, state, line)
    assembly = parse_number(n, "ADD #{mem_addr}\n")
    {assembly, {variables, read_only, address, errors}}
  end

  def parse_expression({:multiply, expression, {:var, name, {}} = var}, {variables, read_only, address, errors} = state, line) do
    {mem_addr, state} = get_mem_addr(var, state, line)
    {expression_code, {variables, read_only, address, errors}} = parse_expression(expression, state, line)
    assembly = "ZERO\nSTORE 8\n#{expression_code}STORE 9\n"
    start = Labels.get_label()
    out = Labels.get_label()
    s = "!#{start}!DEC\nSTORE 9\nLOAD 8\nADD #{mem_addr}\nSTORE 8\nLOAD 9\nJZERO #{out}\nJUMP #{start}\n!#{out}!LOAD 8\n"
    assembly = "#{assembly}JZERO #{out}\n#{s}"
    {assembly, {variables, read_only, address, errors}}
  end

  def parse_expression({:divide, {:number, {a}}, {:number, {b}}}, {variables, read_only, address, errors} = state, line) do
    if (b == 0) do
      {"ZERO\n", state}
    else
      assembly = parse_number(div(a,b))
      {assembly, state}
    end
  end

  def parse_expression({:divide, expression, {:number, {n}}}, {variables, read_only, address, errors} = state, line) do
    #    parse_expression({:divide, {:number, {n}}, expression}, {variables, read_only, address, errors}, line)
    cond do
      n == 0 -> {"ZERO\n", state}
      n == 1 -> parse_expression(expression, state, line)
      true ->
        {expression_code, state} = parse_expression(expression, state, line)
        number = parse_number(n)
        assembly = "ZERO\nSTORE 7\n#{number}STORE 8\n#{expression_code}INC\n"
        start = Labels.get_label()
        out = Labels.get_label()
        assembly = "#{assembly}STORE 9\n!#{start}!LOAD 9\nSUB 8\nJZERO #{out}\nSTORE 9\nLOAD 7\nINC\nSTORE 7\nJUMP #{start}\n!#{out}!LOAD 7\n"
        {assembly, state}
    end
  end

  def parse_expression({:divide, dividend, divider}, {variables, read_only, address, errors} = state, line) do
    {dividend_code, state} = parse_expression(dividend, state, line)
    {divider_code, state} = parse_expression(divider, state, line)
    start = Labels.get_label()
    out = Labels.get_label()
    assembly = "ZERO\nSTORE 7\n#{divider_code}JZERO #{out}\nSTORE 8\n#{dividend_code}INC\nSTORE 9\n"
    assembly = "#{assembly}!#{start}!LOAD 9\nSUB 8\nJZERO #{out}\nSTORE 9\nLOAD 7\nINC\nSTORE 7\nJUMP #{start}\n!#{out}!LOAD 7\n"
    {assembly, state}
  end

  def parse_expression({:mod, {:number, {a}}, {:number, {b}}}, {variables, read_only, address, errors} = state, line) do
    if (b <= 1) do
      {"ZERO\n", state}
    else
      assembly = parse_number(rem(a,b))
      {assembly, state}
    end
  end

  def parse_expression({:mod, expression, {:number, {n}}}, {variables, read_only, address, errors} = state, line) do
    #    parse_expression({:divide, {:number, {n}}, expression}, {variables, read_only, address, errors}, line)
    cond do
      n <= 1 -> {"ZERO\n", state}
      true ->
        {expression_code, state} = parse_expression(expression, state, line)
        number = parse_number(n)
        assembly = "#{number}STORE 8\n#{expression_code}"
        start = Labels.get_label()
        out = Labels.get_label()
        final = Labels.get_label()
        final_out = Labels.get_label()
        assembly = "#{assembly}!#{start}!STORE 9\nSUB 8\nJZERO #{out}\nJUMP #{start}\n!#{out}!LOAD 9\nINC\nSUB 8\nJZERO #{final}\nDEC\nSTORE 9\n!#{final}!LOAD 9\n"
        {assembly, state}
    end
  end

  def parse_expression({:mod, dividend, divider}, {variables, read_only, address, errors} = state, line) do
    {dividend_code, state} = parse_expression(dividend, state, line)
    {divider_code, state} = parse_expression(divider, state, line)
    start = Labels.get_label()
    out = Labels.get_label()
    final = Labels.get_label()
    final_out = Labels.get_label()
    assembly = "ZERO\nSTORE 9\n#{divider_code}JZERO #{final}\nSTORE 8\n#{dividend_code}"
    assembly = "#{assembly}!#{start}!STORE 9\nSUB 8\nJZERO #{out}\nJUMP #{start}\n!#{out}!LOAD 9\nINC\nSUB 8\nJZERO #{final}\nDEC\nSTORE 9\n!#{final}!LOAD 9\n"
    {assembly, state}
  end

  defp calc_arr_mem_addr({{:array, name, {:number, i}}, {_type, size, mem_addr}}, {variables, read_only, address, errors} = state, line) do
    if (i < size) do
      i = i+mem_addr
      assembly = parse_number(i)
      {"#{assembly}", {variables, read_only, address, errors}}
    else
      {"", {variables, read_only, address, [{:out_of_array_range, {name}, line} | errors]}}
    end
  end

  defp calc_arr_mem_addr({{:array, name, {:var, var_name}}, {_type, size, mem_addr}}, {variables, read_only, address, errors} = state, line) do
    assembly = parse_number(mem_addr)
    {mem_addr, state} = get_mem_addr({:var, var_name, {}}, state, line)
    {"#{assembly}ADD #{mem_addr}\n",state}
  end

  defp get_arr_mem_addr({:array, name, _ops} = var, {variables, read_only, address, errors} = state, line) do
    cond do
      Map.has_key?(read_only, name) or Map.has_key?(variables, name) ->
        arr = Map.get_lazy(read_only, name, fn -> Map.get(variables, name) end)
        {type, _size, _mem_addr} = arr
        if (type == :array) do
          calc_arr_mem_addr({var, arr}, state, line)
        else
          {"", {variables, read_only, address, [{:accessing_array_as_var, {name}, line} | errors]}}
        end
      true ->
        {"", {variables, read_only, address, [{:var_not_found, {name}, line} | errors]}}
    end
  end

  defp get_mem_addr({:var, name, {}}, {variables, read_only, address, errors} = state, line) do
    cond do
      Map.has_key?(read_only, name) or Map.has_key?(variables, name) ->
        {type, _size, mem_addr} = Map.get_lazy(read_only, name, fn -> Map.get(variables, name) end)
        if (type == :var) do
          {mem_addr, {variables, read_only, address, errors}}
        else
          {"", {variables, read_only, address, [{:accessing_array_as_var, {name}, line} | errors]}}
        end
      true ->
        {"", {variables, read_only, address, [{:var_not_found, {name}, line} | errors]}}
    end
  end

  defp parse_number_test(n) do
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

  def parse_number(n) do
    parse_number(n, "INC\n")
#    bits = Integer.to_string(n, 2)
#    bits = String.split(bits, "0", trim: false)
#    code = Enum.map(bits, fn b ->
#      if (String.length(b) > 3)do
#        "INC\n" <> String.duplicate("SHL\n", String.length(b)) <> "DEC\n"
#      else
#        if (String.length(b) > 0) do
#          String.duplicate("SHL\nINC\n", max(String.length(b), 0))
#        end
#      end
#    end) |> Enum.join("SHL\n") |> String.trim_leading("SHL\n")
#    "ZERO\n" <> code
  end

  defp parse_number(n, assembly) do
    bits = Integer.to_string(n, 2)
    bits = String.split(bits, "0", trim: false)
    code = Enum.map(bits, fn b ->
      if (String.length(b) > 3)do
        "#{assembly}" <> String.duplicate("SHL\n", String.length(b)) <> "DEC\n"
      else
        if (String.length(b) > 0) do
          String.duplicate("SHL\n#{assembly}", max(String.length(b), 0))
        end
      end
    end) |> Enum.join("SHL\n") |> String.trim_leading("SHL\n")
    "ZERO\n" <> code
  end

  def lines(s) do
    s |> String.split |> Enum.count
  end

end
