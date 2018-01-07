defmodule Compiler.Code do
  @moduledoc false
  alias Compiler.Labels, as: Labels

  def gen_assembly([], {_variables, _read_only, _address, errors} = _state, assembly) do
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

  defp parse_cmd(cmd, state) when is_binary(cmd) do
    {cmd, state}
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
      Map.has_key?(read_only, name) or Map.has_key?(variables, name) ->
        var = Map.get_lazy(read_only, name, fn -> Map.get(variables, name) end)
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
    parse_condition({condition, cmds, []}, state, line)
  end

  defp parse_cmd({line, :ifelse, {condition, if_cmds, else_cmds}}, {variables, read_only, address, errors} = state) do
    parse_condition({condition, if_cmds, else_cmds}, state, line)
  end

  defp parse_cmd({line, :while, {condition, cmds}}, {variables, read_only, address, errors} = state) when is_list(cmds) do
    start = Labels.get_label()
    {assembly, state} = parse_condition({condition, cmds ++ ["JUMP #{start}\n"], []}, state, line)
    {"!#{start}!#{assembly}", state}
  end

  defp parse_cmd({line, :for, {name, from, to, cmds, dir} = for}, {variables, read_only, address, errors} = state) do
    {assembly, {_variables, _read_only, _address, errors}} = parse_for(for, {variables, read_only, address, errors}, line)
    {assembly, {variables, read_only, address, errors}}
  end

  defp parse_for({name, {:number, {from}}, {:number, {to}}, cmds, :to}, {variables, read_only, address, errors} = state, line) do
    i_addr = address
    end_addr = address+1
    read = Map.put(read_only, name, {:var, 1, i_addr})
    i_assembly = "#{parse_number(from)}STORE #{i_addr}\n"
    cond do
      from == to ->
        {_, assembly, errors} = gen_assembly(cmds, {variables, read, address+2, errors}, "")
        {"#{i_assembly}#{assembly}", {variables, read_only, address, errors}}
      from < to ->
        {_, code_assembly, errors} = gen_assembly(cmds, {variables, read, address+2, errors}, "")

        skip = Labels.get_label()
        start = Labels.get_label()

        assembly = "#{i_assembly}#{parse_number(to+1)}STORE #{end_addr}\n!#{start}!SUB #{i_addr}\nJZERO #{skip}\n#{code_assembly}LOAD #{i_addr}\nINC\nSTORE #{i_addr}\nLOAD #{end_addr}\nJUMP #{start}\n!#{skip}!"

        {assembly, {variables, read_only, address, errors}}
    end
  end

  defp parse_for({name, {:number, {from}}, {:var, to_name, {}} = to, cmds, :to}, {variables, read_only, address, errors} = state, line) do
    {mem_addr, {variables, read_only, address, errors}} = get_mem_addr(to, state, line)

    i_addr = address
    end_addr = address+1
    read = Map.put(read_only, name, {:var, 1, i_addr})
    i_assembly = "#{parse_number(from)}STORE #{i_addr}\n"

    {_, code_assembly, errors} = gen_assembly(cmds, {variables, read, address+2, errors}, "")

    skip = Labels.get_label()
    start = Labels.get_label()

#    assembly = "#{i_assembly}LOAD #{mem_addr}\nINC\nSUB #{i_addr}\nSTORE #{end_addr}\n!#{start}!LOAD #{end_addr}\nJZERO #{skip}\nDEC\nSTORE #{end_addr}\n#{code_assembly}LOAD #{i_addr}\nINC\nSTORE #{i_addr}\nJUMP #{start}\n!#{skip}!"

    assembly = "#{i_assembly}LOAD #{mem_addr}\nINC\nSTORE #{end_addr}\n!#{start}!SUB #{i_addr}\nJZERO #{skip}\n#{code_assembly}LOAD #{i_addr}\nINC\nSTORE #{i_addr}\nLOAD #{end_addr}\nJUMP #{start}\n!#{skip}!"

    {assembly, {variables, read_only, address, errors}}
  end

  defp parse_for({name, {:var, from_name, {}} = from, {:number, {to}}, cmds, :to}, {variables, read_only, address, errors} = state, line) do
    {mem_addr, {variables, read_only, address, errors}} = get_mem_addr(from, state, line)

    i_addr = address
    end_addr = address+1
    read = Map.put(read_only, name, {:var, 1, i_addr})
    i_assembly = "LOAD #{mem_addr}\nSTORE #{i_addr}\n"

    {_, code_assembly, errors} = gen_assembly(cmds, {variables, read, address+2, errors}, "")

    skip = Labels.get_label()
    start = Labels.get_label()

    assembly = "#{i_assembly}#{parse_number(to+1)}STORE #{end_addr}\n!#{start}!SUB #{i_addr}\nJZERO #{skip}\n#{code_assembly}LOAD #{i_addr}\nINC\nSTORE #{i_addr}\nLOAD #{end_addr}\nJUMP #{start}\n!#{skip}!"

    {assembly, {variables, read_only, address, errors}}
  end

  defp parse_for({name, from, to, cmds, :to}, {variables, read_only, address, errors} = state, line) do
    {from_code, state} = parse_expression(from, state, line)
    {to_code, {variables, read_only, address, errors}} = parse_expression(to, state, line)

    i_addr = address
    end_addr = address+1
    read = Map.put(read_only, name, {:var, 1, i_addr})

    {_, code_assembly, errors} = gen_assembly(cmds, {variables, read, address+2, errors}, "")

    i_assembly = "#{from_code}STORE #{i_addr}\n"

    skip = Labels.get_label()
    start = Labels.get_label()

#    assembly = "#{i_assembly}#{to_code}INC\nSUB #{i_addr}\nSTORE #{end_addr}\n!#{start}!LOAD #{end_addr}\nJZERO #{skip}\nDEC\nSTORE #{end_addr}\n#{code_assembly}LOAD #{i_addr}\nINC\nSTORE #{i_addr}\nJUMP #{start}\n!#{skip}!"

    assembly = "#{i_assembly}#{to_code}INC\nSTORE #{end_addr}\n!#{start}!SUB #{i_addr}\nJZERO #{skip}\n#{code_assembly}LOAD #{i_addr}\nINC\nSTORE #{i_addr}\nLOAD #{end_addr}\nJUMP #{start}\n!#{skip}!"

    {assembly, {variables, read_only, address, errors}}
  end

  defp parse_for({name, from, to, cmds, :to}, {variables, read_only, address, errors} = state, line) do
    {from_code, state} = parse_expression(from, state, line)
    {to_code, {variables, read_only, address, errors}} = parse_expression(to, state, line)

    i_addr = address
    end_addr = address+1
    read = Map.put(read_only, name, {:var, 1, i_addr})

    {_, code_assembly, errors} = gen_assembly(cmds, {variables, read, address+2, errors}, "")

    i_assembly = "#{from_code}STORE #{i_addr}\n"

    skip = Labels.get_label()
    start = Labels.get_label()

    assembly = "#{i_assembly}#{to_code}INC\nSUB #{i_addr}\nSTORE #{end_addr}\n!#{start}!LOAD #{end_addr}\nJZERO #{skip}\nDEC\nSTORE #{end_addr}\n#{code_assembly}LOAD #{i_addr}\nINC\nSTORE #{i_addr}\nJUMP #{start}\n!#{skip}!"

    {assembly, {variables, read_only, address, errors}}
  end

  defp parse_for({name, from, to, cmds, :downto}, {variables, read_only, address, errors} = state, line) do
    {from_code, state} = parse_expression(from, state, line)
    {to_code, {variables, read_only, address, errors}} = parse_expression(to, state, line)

    i_addr = address
    end_addr = address+1
    read = Map.put(read_only, name, {:var, 1, i_addr})

    {_, code_assembly, errors} = gen_assembly(cmds, {variables, read, address+2, errors}, "")

    skip = Labels.get_label()
    start = Labels.get_label()
    full_skip = Labels.get_label()

#    assembly = "#{to_code}STORE 9\n#{i_assembly}INC\nSUB 9\nSTORE #{end_addr}\n!#{start}!LOAD #{end_addr}\nJZERO #{skip}\nDEC\nSTORE #{end_addr}\n#{code_assembly}LOAD #{i_addr}\nDEC\nSTORE #{i_addr}\nJUMP #{start}\n!#{skip}!"

    i_assembly = "#{from_code}STORE #{i_addr}\n"
    store_code = "#{to_code}STORE #{end_addr}\n#{i_assembly}SUB #{end_addr}\nJZERO #{full_skip}\nLOAD #{i_addr}\n"
    assembly = "#{store_code}!#{start}!SUB #{end_addr}\nJZERO #{skip}\n#{code_assembly}LOAD #{i_addr}\nDEC\nSTORE #{i_addr}\nJUMP #{start}\n!#{skip}!#{code_assembly}!#{full_skip}!"

    {assembly, {variables, read_only, address, errors}}
  end

  defp parse_condition({{:equals, {:number, {a}}, {:number, {b}}}, if_cmds, else_cmds}, {variables, read_only, address, errors} = state, line) do
    if (a == b) do
      {_, assembly, errors} = gen_assembly(if_cmds, state, "")
      {assembly, {variables, read_only, address, errors}}
    else
      {_, assembly, errors} = gen_assembly(else_cmds, state, "")
      {assembly, {variables, read_only, address, errors}}
    end
  end

  defp parse_condition({{:equals, {:number, {n}}, {:var, name, {}} = var}, if_cmds, else_cmds}, {variables, read_only, address, errors} = state, line) do
    parse_condition({{:equals, var, {:number, {n}}}, if_cmds, else_cmds}, state, line)
  end

  defp parse_condition({{:equals, {:var, name, {}} = var, value}, if_cmds, else_cmds}, {variables, read_only, address, errors} = state, line) do
    {value_code, state} = parse_expression(value, state, line)
    {mem_addr, state} = get_mem_addr(var, state, line)
    go_else = Labels.get_label()
    start = Labels.get_label()
    skip = Labels.get_label()
    code = "#{value_code}INC\nSUB #{mem_addr}\nJZERO #{go_else}\nDEC\nJZERO #{start}\nJUMP #{go_else}\n!#{start}!"
    {_, assembly, errors} = gen_assembly(if_cmds, state, "")
    case else_cmds do
      [] -> {"#{code}#{assembly}!#{go_else}!", {variables, read_only, address, errors}}
      _ ->
        {_, else_assembly, errors} = gen_assembly(else_cmds, {variables, read_only, address, errors}, "")
        {"#{code}#{assembly}JUMP #{skip}\n!#{go_else}!#{else_assembly}!#{skip}!", {variables, read_only, address, errors}}
    end
  end

  defp parse_condition({{:equals, {:array, name, _ops} = var, value}, if_cmds, else_cmds}, {variables, read_only, address, errors} = state, line) do
    {value_code, state} = parse_expression(value, state, line)
    {array_code, state} = get_arr_mem_addr(var, state, line)
    go_else = Labels.get_label()
    start = Labels.get_label()
    skip = Labels.get_label()
    code = "#{array_code}STORE 1\n#{value_code}INC\nSUBI 1\nJZERO #{go_else}\nDEC\nJZERO #{start}\nJUMP #{go_else}\n!#{start}!"
    {_, assembly, errors} = gen_assembly(if_cmds, state, "")
    case else_cmds do
      [] -> {"#{code}#{assembly}!#{go_else}!", {variables, read_only, address, errors}}
      _ ->
        {_, else_assembly, errors} = gen_assembly(else_cmds, {variables, read_only, address, errors}, "")
        {"#{code}#{assembly}JUMP #{skip}\n!#{go_else}!#{else_assembly}!#{skip}!", {variables, read_only, address, errors}}
    end
    #    {"#{code}#{assembly}!#{go_else}!", {variables, read_only, address, errors}}
  end

  defp parse_condition({{:ne, {:number, {a}}, {:number, {b}}}, if_cmds, else_cmds}, {variables, read_only, address, errors} = state, line) do
    if (a != b) do
      {_, assembly, errors} = gen_assembly(if_cmds, state, "")
      {assembly, {variables, read_only, address, errors}}
    else
      {_, assembly, errors} = gen_assembly(else_cmds, state, "")
      {assembly, {variables, read_only, address, errors}}
    end
  end

  defp parse_condition({{:ne, {:number, {n}}, {:var, name, {}} = var}, if_cmds, else_cmds}, {variables, read_only, address, errors} = state, line) do
    parse_condition({{:ne, var, {:number, {n}}}, if_cmds, else_cmds}, state, line)
  end

  defp parse_condition({{:ne, {:var, name, {}} = var, value}, if_cmds, else_cmds}, {variables, read_only, address, errors} = state, line) do
    {value_code, state} = parse_expression(value, state, line)
    {mem_addr, state} = get_mem_addr(var, state, line)
    go_else = Labels.get_label()
    start = Labels.get_label()
    skip = Labels.get_label()
    code = "#{value_code}INC\nSUB #{mem_addr}\nJZERO #{start}\nDEC\nJZERO #{go_else}\n!#{start}!"
    {_, assembly, errors} = gen_assembly(if_cmds, state, "")
    case else_cmds do
      [] -> {"#{code}#{assembly}!#{go_else}!", {variables, read_only, address, errors}}
      _ ->
        {_, else_assembly, errors} = gen_assembly(else_cmds, {variables, read_only, address, errors}, "")
        {"#{code}#{assembly}JUMP #{skip}\n!#{go_else}!#{else_assembly}!#{skip}!", {variables, read_only, address, errors}}
    end
    #    {"#{code}#{assembly}!#{go_else}!", {variables, read_only, address, errors}}
  end

  defp parse_condition({{:ne, {:array, name, _ops} = var, value}, if_cmds, else_cmds}, {variables, read_only, address, errors} = state, line) do
    {value_code, state} = parse_expression(value, state, line)
    {array_code, state} = get_arr_mem_addr(var, state, line)
    go_else = Labels.get_label()
    start = Labels.get_label()
    skip = Labels.get_label()
    code = "#{array_code}STORE 1\n#{value_code}INC\nSUBI 1\nJZERO #{start}\nDEC\nJZERO #{go_else}\n!#{start}!"
    {_, assembly, errors} = gen_assembly(if_cmds, state, "")
    case else_cmds do
      [] -> {"#{code}#{assembly}!#{go_else}!", {variables, read_only, address, errors}}
      _ ->
        {_, else_assembly, errors} = gen_assembly(else_cmds, {variables, read_only, address, errors}, "")
        {"#{code}#{assembly}JUMP #{skip}\n!#{go_else}!#{else_assembly}!#{skip}!", {variables, read_only, address, errors}}
    end
    #    {"#{code}#{assembly}!#{go_else}!", {variables, read_only, address, errors}}
  end

  defp parse_condition({{:l, {:var, _name, {}} = left, right}, if_cmds, else_cmds}, {variables, read_only, address, errors} = state, line) do
    {mem_addr, state} = get_mem_addr(left, state, line)
    {right_code, state} = parse_expression(right, state, line)

    go_else = Labels.get_label()
    #    start = Labels.get_label()
    skip = Labels.get_label()

    code = "#{right_code}SUB #{mem_addr}\nJZERO #{go_else}\n"
    {_, assembly, errors} = gen_assembly(if_cmds, state, "")
    case else_cmds do
      [] -> {"#{code}#{assembly}!#{go_else}!", {variables, read_only, address, errors}}
      _ ->
        {_, else_assembly, errors} = gen_assembly(else_cmds, {variables, read_only, address, errors}, "")
        {"#{code}#{assembly}JUMP #{skip}\n!#{go_else}!#{else_assembly}!#{skip}!", {variables, read_only, address, errors}}
    end
  end

  defp parse_condition({{:l, {:var, _name, {}} = left, right}, if_cmds, else_cmds}, {variables, read_only, address, errors} = state, line) do
    {mem_addr, state} = get_mem_addr(left, state, line)
    {right_code, state} = parse_expression(right, state, line)

    go_else = Labels.get_label()
    #    start = Labels.get_label()
    skip = Labels.get_label()

    code = "#{right_code}SUB #{mem_addr}\nJZERO #{go_else}\n"
    {_, assembly, errors} = gen_assembly(if_cmds, state, "")
    case else_cmds do
      [] -> {"#{code}#{assembly}!#{go_else}!", {variables, read_only, address, errors}}
      _ ->
        {_, else_assembly, errors} = gen_assembly(else_cmds, {variables, read_only, address, errors}, "")
        {"#{code}#{assembly}JUMP #{skip}\n!#{go_else}!#{else_assembly}!#{skip}!", {variables, read_only, address, errors}}
    end
  end

  # left < right
  # 0 < right - left
  # dla false: 0 >= right - left
  defp parse_condition({{:l, left, right}, if_cmds, else_cmds}, {variables, read_only, address, errors} = state, line) do
    {left_code, state} = parse_expression(left, state, line)
    {right_code, state} = parse_expression(right, state, line)

    go_else = Labels.get_label()
#    start = Labels.get_label()
    skip = Labels.get_label()

    code = "#{left_code}STORE 9\n#{right_code}SUB 9\nJZERO #{go_else}\n"
    {_, assembly, errors} = gen_assembly(if_cmds, state, "")
    case else_cmds do
      [] -> {"#{code}#{assembly}!#{go_else}!", {variables, read_only, address, errors}}
      _ ->
        {_, else_assembly, errors} = gen_assembly(else_cmds, {variables, read_only, address, errors}, "")
        {"#{code}#{assembly}JUMP #{skip}\n!#{go_else}!#{else_assembly}!#{skip}!", {variables, read_only, address, errors}}
    end
  end

  # left <= right
  # left - right <= 0
  #
  defp parse_condition({{:le, left, right}, if_cmds, else_cmds}, {variables, read_only, address, errors} = state, line) do
    {left_code, state} = parse_expression(left, state, line)
    {right_code, state} = parse_expression(right, state, line)

    go_else = Labels.get_label()
    start = Labels.get_label()
    skip = Labels.get_label()

#    code = "#{right_code}STORE 9\n#{left_code}SUB 9\nJZERO #{start}\nJUMP #{go_else}\n!#{start}!"
    code = "#{right_code}STORE 9\n#{left_code}SUB 9\nJZERO #{start}\nJUMP #{go_else}\n!#{start}!"
    {_, assembly, errors} = gen_assembly(if_cmds, state, "")
    case else_cmds do
      [] -> {"#{code}#{assembly}!#{go_else}!", {variables, read_only, address, errors}}
      _ ->
        {_, else_assembly, errors} = gen_assembly(else_cmds, {variables, read_only, address, errors}, "")
        {"#{code}#{assembly}JUMP #{skip}\n!#{go_else}!#{else_assembly}!#{skip}!", {variables, read_only, address, errors}}
    end
  end

  defp parse_condition({{:g, left, right}, if_cmds, else_cmds}, {variables, read_only, address, errors} = state, line) do
    parse_condition({{:l, right, left}, if_cmds, else_cmds}, {variables, read_only, address, errors} = state, line)
  end

  defp parse_condition({{:ge, left, right}, if_cmds, else_cmds}, {variables, read_only, address, errors} = state, line) do
    parse_condition({{:le, right, left}, if_cmds, else_cmds}, {variables, read_only, address, errors} = state, line)
  end

  defp put({{:var, name, {}}, {_type, _size, mem_addr}}, state, _line) do
    {"LOAD #{mem_addr}\nPUT\n", state}
  end

  defp put({{:array, _name, {:number, i}}, {_type, _size, _mem_addr}} = var, {variables, read_only, address, errors} = state, line) do
    {mem_addr, state} = calc_arr_mem_addr_i(var, state, line)
    {"LOAD #{mem_addr}\nPUT\n", state}
  end

  defp put({{:array, _name, _ops}, {_type, _size, _mem_addr}} = var, {variables, read_only, address, errors} = state, line) do
    {assembly, state} = calc_arr_mem_addr(var, state, line)
    {"#{assembly}STORE 0\nLOADI 0\nPUT\n",state}
  end

  defp assign({{:var, name, {}}, {_type, _size, mem_addr}}, expression, state, line) do
    {expression_code, {variables, read_only, address, errors}} = parse_expression(expression, state, line)
    Compiler.Initialized.initialize(name)
    {"#{expression_code}STORE #{mem_addr}\n", {variables, read_only, address, errors}}
  end

  defp assign({{:array, _name, {:number, i}}, {_type, _size, _mem_addr}} = var, expression, {variables, read_only, address, errors} = state, line) do
    {mem_addr, state} = calc_arr_mem_addr_i(var, state, line)
    {expression_code, {variables, read_only, address, errors}} = parse_expression(expression, state, line)
    {"#{expression_code}STORE #{mem_addr}\n",{variables, read_only, address, errors}}
  end

  defp assign({{:array, _name, _ops}, {_type, _size, _mem_addr}} = var, expression, {variables, read_only, address, errors} = state, line) do
    {expression_code, {variables, read_only, address, errors}} = parse_expression(expression, state, line)
    {assembly, state} = calc_arr_mem_addr(var, state, line)
    {"#{assembly}STORE 0\n#{expression_code}STOREI 0\n",state}
  end

  def parse_expression(code, {variables, read_only, address, errors}, line) when is_binary(code) do
    {code, {variables, read_only, address, errors}}
  end

  def parse_expression({:number, {n}}, {variables, read_only, address, errors}, line) do
    assembly = parse_number(n)
    {assembly, {variables, read_only, address, errors}}
  end

  def parse_expression({:var, _name, {}} = var, {variables, read_only, address, errors} = state, line) do
    {mem_addr, state} = get_mem_addr(var, state, line)
    {"LOAD #{mem_addr}\n", state}
  end

  def parse_expression({:array, _name, {:number, i}} = var, {variables, read_only, address, errors} = state, line) do
    {mem_addr, state} = get_arr_mem_addr_i(var, state, line)
    {"LOAD #{mem_addr}\n", state}
  end

  def parse_expression({:array, _name, _ops} = var, {variables, read_only, address, errors} = state, line) do
    {assembly, state} = get_arr_mem_addr(var, state, line)
    {"#{assembly}STORE 1\nLOADI 1\n", state}
  end

  def parse_expression({:add, {:number, {a}}, {:number, {b}}}, {variables, read_only, address, errors} = state, line) do
    assembly = parse_number(a+b)
    {assembly, state}
  end

  def parse_expression({:add, {:number, {n}}, expression}, {variables, read_only, address, errors}, line) do
    parse_expression({:add, expression, {:number, {n}}}, {variables, read_only, address, errors}, line)
  end

  def parse_expression({:add, {:var, name, {}} = var, expression}, {variables, read_only, address, errors} = state, line) do
    {mem_addr, state} = get_mem_addr(var, state, line)
    {expression_code, {variables, read_only, address, errors}} = parse_expression(expression, state, line)
    {"#{expression_code}ADD #{mem_addr}\n",{variables, read_only, address, errors}}
  end

  def parse_expression({:add, {:array, name, {:number, i}} = var, expression}, {variables, read_only, address, errors} = state, line) do
    {mem_addr, state} = get_arr_mem_addr(var, state, line)
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

  def parse_expression({:add, {:array, name, {:number, i}} = var, expression}, {variables, read_only, address, errors} = state, line) do
    {mem_addr, state} = get_arr_mem_addr(var, state, line)
    {expression_code, {variables, read_only, address, errors}} = parse_expression(expression, state, line)
    {"#{expression_code}SUB #{mem_addr}\n",{variables, read_only, address, errors}}
  end

  def parse_expression({:sub, expression, {:array, name, _ops} = var}, {variables, read_only, address, errors} = state, line) do
    {array_code, state} = get_arr_mem_addr(var, state, line)
    {expression_code, {variables, read_only, address, errors}} = parse_expression(expression, state, line)
    {"#{array_code}STORE 2\n#{expression_code}SUBI 2\n", {variables, read_only, address, errors}}
  end

  def parse_expression({:sub, left, right}, state, line) do
    {left_code, state} = parse_expression(left, state, line)
    {right_code, state} = parse_expression(right, state, line)

    {"#{right_code}STORE 9\n#{left_code}SUB 9\n", state}

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

  def parse_expression({:multiply, {:number, {n}}, {:array, name, {:number, i}} = var}, {variables, read_only, address, errors} = state, line) do
    {mem_addr, {variables, read_only, address, errors}} = get_arr_mem_addr_i(var, state, line)
    assembly = parse_number(n, "ADD #{mem_addr}\n")
    {assembly, {variables, read_only, address, errors}}
  end

  def parse_expression({:multiply, left, right}, {variables, read_only, address, errors} = state, line) do
    {left_code, state} = parse_expression(left, state, line)
    {right_code, state} = parse_expression(right, state, line)

    skip = Labels.get_label()
    add_skip = Labels.get_label()
    add = Labels.get_label()
    start = Labels.get_label()
    check_skip = Labels.get_label()

    check = "STORE 7\nSUB 8\nJZERO #{check_skip}\nLOAD 7\nSTORE 5\nLOAD 8\nSTORE 7\nLOAD 5\nSTORE 8\n!#{check_skip}!LOAD 7\n"


    store_code = "ZERO\nSTORE 9\n#{left_code}STORE 8\n#{right_code}"
    assembly = "#{store_code}#{check}!#{start}!STORE 7\nJZERO #{skip}\nJODD #{add}\nJUMP #{add_skip}\n!#{add}!LOAD 9\nADD 8\nSTORE 9\n!#{add_skip}!LOAD 8\nSHL\nSTORE 8\nLOAD 7\nSHR\nJUMP #{start}\n!#{skip}!LOAD 9\n"

    {assembly, state}
  end
#
#  def parse_expression({:multiply, expression, {:var, name, {}} = var}, {variables, read_only, address, errors} = state, line) do
#    {mem_addr, state} = get_mem_addr(var, state, line)
#    {expression_code, {variables, read_only, address, errors}} = parse_expression(expression, state, line)
#    assembly = "ZERO\nSTORE 8\n#{expression_code}STORE 9\n"
#    start = Labels.get_label()
#    out = Labels.get_label()
#    s = "!#{start}!DEC\nSTORE 9\nLOAD 8\nADD #{mem_addr}\nSTORE 8\nLOAD 9\nJZERO #{out}\nJUMP #{start}\n!#{out}!LOAD 8\n"
#    assembly = "#{assembly}JZERO #{out}\n#{s}"
#    {assembly, {variables, read_only, address, errors}}
#  end

  def parse_expression({:divide, {:number, {a}}, {:number, {b}}}, {variables, read_only, address, errors} = state, line) do
    if (b == 0) do
      {"ZERO\n", state}
    else
      assembly = parse_number(div(a,b))
      {assembly, state}
    end
  end

  def parse_expression({:divide, {:number, {n}} = dividend, divider}, {variables, read_only, address, errors} = state, line) do
    #    parse_expression({:divide, {:number, {n}}, expression}, {variables, read_only, address, errors}, line)
    cond do
      n == 0 -> {"ZERO\n", state}
      true ->
        {dividend_code, state} = parse_expression(dividend, state, line)
        {divider_code, state} = parse_expression(divider, state, line)

        shr = Labels.get_label()
        out = Labels.get_label()
        power = Labels.get_label()
        full_out = Labels.get_label()

        store_code = "ZERO\nSTORE 9\nINC\nSTORE 6\n#{divider_code}JZERO #{full_out}\nSTORE 7\n#{dividend_code}STORE 8\n"


        power_code = "!#{power}!INC\nSUB 7\nJZERO #{shr}\nDEC\nJZERO #{out}\nLOAD 7\nSHL\nSTORE 7\nLOAD 6\nSHL\nSTORE 6\nLOAD 8\nJUMP #{power}\n!#{shr}!"

        assembly = "LOAD 6\nSHR\nSTORE 6\nJZERO #{out}\nLOAD 7\nSHR\nSTORE 7\nLOAD 8\nINC\nSUB 7\nJZERO #{shr}\nDEC\nSTORE 8\nLOAD 6\nADD 9\nSTORE 9\nJUMP #{shr}\n!#{out}!LOAD 9\nADD 6\n!#{full_out}!"

        {"#{store_code}#{power_code}#{assembly}", state}
    end
  end

  def parse_expression({:divide, dividend, {:number, {n}} = divider}, {variables, read_only, address, errors} = state, line) do
    #    parse_expression({:divide, {:number, {n}}, expression}, {variables, read_only, address, errors}, line)
    cond do
      n == 0 -> {"ZERO\n", state}
      n == 1 -> parse_expression(dividend, state, line)
      true ->
        {dividend_code, state} = parse_expression(dividend, state, line)
        {divider_code, state} = parse_expression(divider, state, line)

        shr = Labels.get_label()
        out = Labels.get_label()
        power = Labels.get_label()
        full_out = Labels.get_label()

        store_code = "ZERO\nSTORE 9\nINC\nSTORE 6\n#{divider_code}JZERO #{full_out}\nSTORE 7\n#{dividend_code}STORE 8\n"


        power_code = "!#{power}!INC\nSUB 7\nJZERO #{shr}\nDEC\nJZERO #{out}\nLOAD 7\nSHL\nSTORE 7\nLOAD 6\nSHL\nSTORE 6\nLOAD 8\nJUMP #{power}\n!#{shr}!"

        assembly = "LOAD 6\nSHR\nSTORE 6\nJZERO #{out}\nLOAD 7\nSHR\nSTORE 7\nLOAD 8\nINC\nSUB 7\nJZERO #{shr}\nDEC\nSTORE 8\nLOAD 6\nADD 9\nSTORE 9\nJUMP #{shr}\n!#{out}!LOAD 9\nADD 6\n!#{full_out}!"

        {"#{store_code}#{power_code}#{assembly}", state}
    end
  end

#  def parse_expression({:divide, dividend, divider}, {variables, read_only, address, errors} = state, line) do
#    {dividend_code, state} = parse_expression(dividend, state, line)
#    {divider_code, state} = parse_expression(divider, state, line)
#
#    # Euclidean division
#    # r - 6
#    # q - 7
#    # n - 8
#    # aux - 9
#    # http://compoasso.free.fr/primelistweb/page/prime/euclide_en.php
#
#    power_start = Labels.get_label()
#    power_end = Labels.get_label()
#    finish = Labels.get_label()
#    qpp = Labels.get_label()
#    skip_qpp = Labels.get_label()
#    skip_q_shr = Labels.get_label()
#    start = Labels.get_label()
#
#    store_code = "ZERO\nSTORE 7\nSTORE 8\n#{divider_code}JZERO #{finish}\nSTORE 9\n#{dividend_code}STORE 6\n"
#    power_code = "!#{power_start}!INC\nSUB 9\nJZERO #{power_end}\nLOAD 9\nSHL\nSTORE 9\nLOAD 8\nINC\nSTORE 8\nLOAD 6\nJUMP #{power_start}\n!#{power_end}!"
#    assembly = "!#{start}!LOAD 8\nJZERO #{finish}\nDEC\nSTORE 8\nLOAD 9\nSHR\nSTORE 9\nLOAD 6\nINC\nSUB 9\nJZERO #{skip_qpp}\nDEC\nSTORE 6\nLOAD 7\nSHL\nINC\nSTORE 7\nJUMP #{skip_q_shr}\n!#{skip_qpp}!LOAD 7\nSHL\nSTORE 7\n!#{skip_q_shr}!JUMP #{start}\n!#{finish}!LOAD 7\n"
#
#    {"#{store_code}#{power_code}#{assembly}", state}
#
#  end

  def parse_expression({:divide, dividend, divider}, {variables, read_only, address, errors} = state, line) do
    {dividend_code, state} = parse_expression(dividend, state, line)
    {divider_code, state} = parse_expression(divider, state, line)

    shr = Labels.get_label()
    out = Labels.get_label()
    power = Labels.get_label()
    full_out = Labels.get_label()

    store_code = "ZERO\nSTORE 9\nINC\nSTORE 6\n#{divider_code}JZERO #{full_out}\nSTORE 7\n#{dividend_code}STORE 8\n"


    power_code = "!#{power}!INC\nSUB 7\nJZERO #{shr}\nDEC\nJZERO #{out}\nLOAD 7\nSHL\nSTORE 7\nLOAD 6\nSHL\nSTORE 6\nLOAD 8\nJUMP #{power}\n!#{shr}!"

    assembly = "LOAD 6\nSHR\nSTORE 6\nJZERO #{out}\nLOAD 7\nSHR\nSTORE 7\nLOAD 8\nINC\nSUB 7\nJZERO #{shr}\nDEC\nSTORE 8\nLOAD 6\nADD 9\nSTORE 9\nJUMP #{shr}\n!#{out}!LOAD 9\nADD 6\n!#{full_out}!"

    {"#{store_code}#{power_code}#{assembly}", state}

  end

#  def parse_expression({:divide, dividend, divider}, {variables, read_only, address, errors} = state, line) do
#    {dividend_code, state} = parse_expression(dividend, state, line)
#    {divider_code, state} = parse_expression(divider, state, line)
#    start = Labels.get_label()
#    out = Labels.get_label()
#    assembly = "ZERO\nSTORE 7\n#{divider_code}JZERO #{out}\nSTORE 8\n#{dividend_code}INC\nSTORE 9\n"
#    assembly = "#{assembly}!#{start}!LOAD 9\nSUB 8\nJZERO #{out}\nSTORE 9\nLOAD 7\nINC\nSTORE 7\nJUMP #{start}\n!#{out}!LOAD 7\n"
#    {assembly, state}
#  end

  def parse_expression({:mod, {:number, {a}}, {:number, {b}}}, {variables, read_only, address, errors} = state, line) do
    if (b <= 1) do
      {"ZERO\n", state}
    else
      assembly = parse_number(rem(a,b))
      {assembly, state}
    end
  end

  def parse_expression({:mod, dividend, {:number, {n}} = divider}, {variables, read_only, address, errors} = state, line) do
    #    parse_expression({:divide, {:number, {n}}, expression}, {variables, read_only, address, errors}, line)
    cond do
      n <= 1 -> {"ZERO\n", state}
      true ->
        {dividend_code, state} = parse_expression(dividend, state, line)
        {divider_code, state} = parse_expression(divider, state, line)

        shr = Labels.get_label()
        out = Labels.get_label()
        power = Labels.get_label()
        zero = Labels.get_label()
        zero_out = Labels.get_label()

        store_code = "#{divider_code}JZERO #{out}\nSTORE 7\nZERO\nSTORE 9\nINC\nSTORE 6\n#{dividend_code}STORE 8\n"


        power_code = "!#{power}!INC\nSUB 7\nJZERO #{shr}\nDEC\nJZERO #{zero}\nLOAD 7\nSHL\nSTORE 7\nLOAD 6\nSHL\nSTORE 6\nLOAD 8\nJUMP #{power}\n!#{shr}!"

        assembly = "LOAD 6\nSHR\nSTORE 6\nJZERO #{out}\nLOAD 7\nSHR\nSTORE 7\nLOAD 8\nINC\nSUB 7\nJZERO #{shr}\nDEC\nSTORE 8\nJUMP #{shr}\n!#{zero}!ZERO\nJUMP #{zero_out}\n!#{out}!LOAD 8\n!#{zero_out}!"

        {"#{store_code}#{power_code}#{assembly}", state}
    end
  end

  def parse_expression({:mod, {:number, {n}} = dividend, divider}, {variables, read_only, address, errors} = state, line) do
    #    parse_expression({:divide, {:number, {n}}, expression}, {variables, read_only, address, errors}, line)
    cond do
      n == 0 -> {"ZERO\n", state}
      true ->
        {dividend_code, state} = parse_expression(dividend, state, line)
        {divider_code, state} = parse_expression(divider, state, line)

        shr = Labels.get_label()
        out = Labels.get_label()
        power = Labels.get_label()
        zero = Labels.get_label()
        zero_out = Labels.get_label()

        store_code = "#{divider_code}JZERO #{out}\nSTORE 7\nZERO\nSTORE 9\nINC\nSTORE 6\n#{dividend_code}STORE 8\n"


        power_code = "!#{power}!INC\nSUB 7\nJZERO #{shr}\nDEC\nJZERO #{zero}\nLOAD 7\nSHL\nSTORE 7\nLOAD 6\nSHL\nSTORE 6\nLOAD 8\nJUMP #{power}\n!#{shr}!"

        assembly = "LOAD 6\nSHR\nSTORE 6\nJZERO #{out}\nLOAD 7\nSHR\nSTORE 7\nLOAD 8\nINC\nSUB 7\nJZERO #{shr}\nDEC\nSTORE 8\nJUMP #{shr}\n!#{zero}!ZERO\nJUMP #{zero_out}\n!#{out}!LOAD 8\n!#{zero_out}!"

        {"#{store_code}#{power_code}#{assembly}", state}
    end
  end

  def parse_expression({:mod, dividend, divider}, {variables, read_only, address, errors} = state, line) do
    {dividend_code, state} = parse_expression(dividend, state, line)
    {divider_code, state} = parse_expression(divider, state, line)

    shr = Labels.get_label()
    out = Labels.get_label()
    power = Labels.get_label()
    zero = Labels.get_label()
    zero_out = Labels.get_label()

    store_code = "#{divider_code}JZERO #{out}\nSTORE 7\nZERO\nSTORE 9\nINC\nSTORE 6\n#{dividend_code}STORE 8\n"


    power_code = "!#{power}!INC\nSUB 7\nJZERO #{shr}\nDEC\nJZERO #{zero}\nLOAD 7\nSHL\nSTORE 7\nLOAD 6\nSHL\nSTORE 6\nLOAD 8\nJUMP #{power}\n!#{shr}!"

    assembly = "LOAD 6\nSHR\nSTORE 6\nJZERO #{out}\nLOAD 7\nSHR\nSTORE 7\nLOAD 8\nINC\nSUB 7\nJZERO #{shr}\nDEC\nSTORE 8\nJUMP #{shr}\n!#{zero}!ZERO\nJUMP #{zero_out}\n!#{out}!LOAD 8\n!#{zero_out}!"

    {"#{store_code}#{power_code}#{assembly}", state}
  end

  defp calc_arr_mem_addr_i({{:array, name, {:number, i}}, {_type, size, mem_addr}}, {variables, read_only, address, errors} = state, line) do
    cond do
      Map.has_key?(read_only, name) or Map.has_key?(variables, name) ->
        {type, size, mem_addr} = Map.get_lazy(read_only, name, fn -> Map.get(variables, name) end)
        if (type == :array) do
          if (size > i) do
            {mem_addr+i, {variables, read_only, address, errors}}
          else
            {"", {variables, read_only, address, [{:out_of_array_range, {name}, line} | errors]}}
          end
        else
          {"", {variables, read_only, address, [{:accessing_var_as_array, {name}, line} | errors]}}
        end
      true ->
        {"", {variables, read_only, address, [{:var_not_found, {name}, line} | errors]}}
    end
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
    #  defp get_arr_mem_addr({:array, name, {:var, _var_name}} = var, {variables, read_only, address, errors} = state, line) do
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

  defp get_arr_mem_addr_i({:array, name, _ops} = var, {variables, read_only, address, errors} = state, line) do
    #  defp get_arr_mem_addr({:array, name, {:var, _var_name}} = var, {variables, read_only, address, errors} = state, line) do
    cond do
      Map.has_key?(read_only, name) or Map.has_key?(variables, name) ->
        arr = Map.get_lazy(read_only, name, fn -> Map.get(variables, name) end)
        {type, _size, _mem_addr} = arr
        if (type == :array) do
          calc_arr_mem_addr_i({var, arr}, state, line)
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
          if (Map.has_key?(read_only, name) || Compiler.Initialized.is_initialized?(name)) do
            {mem_addr, {variables, read_only, address, errors}}
          else
            {"", {variables, read_only, address, [{:variable_not_initialized, {name}, line} | errors]}}
          end
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
