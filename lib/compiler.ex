defmodule Compiler do

  def run(filename) do
    Compiler.Labels.start_link()
    {:ok, file} = File.open(filename, [:read])
    program = IO.read(file, :all)
    File.close(file)
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
    res = parse(res)
    case res do
      {:ok, assembly} ->
        IO.inspect(assembly)
        {:ok, labels, _} = :label_lexer.string(String.to_charlist(assembly))

        assembly = clear_labels(labels, assembly)

        IO.inspect(labels)
        {:ok, file} = File.open(filename <> ".out", [:write])
        IO.write(file, assembly)
        IO.write(file, "HALT\n")
        File.close(file)
      {:error, errors} ->
        IO.inspect(errors)
    end
  end

  defp clear_labels([], code) do
    code
  end

  defp clear_labels([{label, line_no}], code) do
    label = List.to_string(label)
    code |> String.replace("!" <> label <> "!", "") |> String.replace(label, "#{line_no}")
  end

  defp clear_labels([{label, line_no} | labels], code) do
    label = List.to_string(label)
    code = code |> String.replace("!" <> label <> "!", "") |> String.replace(label, "#{line_no}")
    clear_labels(labels, code)
  end

  defp parse(%{code: code, declarations: declarations}) do
    a = Compiler.Declarations.prepare_variable_map(declarations)
    IO.inspect(a)
    {variables, address, errors} = a
    Compiler.Code.gen_assembly(code, {variables, %{}, address, errors}, "")
  end



end
