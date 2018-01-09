defmodule Compiler do

  def main(args \\ []) do
    IO.inspect("aaaaaaaaaaaa")
  end

  def run(in_filename) when is_binary(in_filename) do
    run(in_filename, "a.out")
  end

  def run(in_filename, out_filename) when is_binary(in_filename) and is_binary(out_filename) do
    Compiler.Labels.start_link()
    Compiler.Initialized.start_link()
    Compiler.Acumulator.start_link()

    {:ok, file} = File.open(in_filename, [:read])
    program = IO.read(file, :all)
    File.close(file)

    program = String.to_charlist(program)

    lexed = :compiler_lexer.string(program)

    case lexed do
      {:ok, tokens, lines} ->
        parsed = :compiler_parser.parse(tokens)

        case parsed do
          {:ok, res} ->
            res = parse(res)
            case res do
              {:ok, assembly, _} ->
                {:ok, labels, _} = :label_lexer.string(String.to_charlist(assembly))

                labels = labels |> Enum.map(fn {label, line_no} -> {String.trim(to_string(label), "!"), line_no} end)

                assembly = clear_labels(labels, assembly)

                {:ok, file} = File.open(out_filename, [:write])
                IO.write(file, assembly)
                IO.write(file, "HALT\n")
                File.close(file)

              {:error, _, errors} ->
                errors = Enum.reverse(errors)
                Enum.each(errors, fn {msg, info, line_no} ->
                  IO.puts(:stderr, "Error at line: #{line_no}: #{inspect msg} (#{inspect info})")
                end)
            end
          {:error, {line_no, :compiler_parser, info}} ->
            IO.puts(:stderr, "Error at line: #{line_no}\n#{Enum.join(info, "")}\n\n")
        end
      {:error, {line_no, :compiler_lexer, {:illegal, _}}, lines_readed} ->
        IO.puts(:stderr, "Unknown command at line: #{line_no}\n\n")
      {:error, {line_no, :compiler_lexer, {:user, command}}, lines_readed} ->
        IO.puts(:stderr, "Unknown command \"#{command}\" at line: #{line_no}\n\n")
    end
  end

  defp clear_labels([], code) do
    code |> String.replace(~r/![^!]+!/, "")
  end

  defp clear_labels([{label, line_no}], code) do
    code = code |> String.replace(label, "#{line_no}")
    clear_labels([], code)
  end

  defp clear_labels([{label, line_no} | labels], code) do
    code = code |> String.replace(label, "#{line_no}")
    clear_labels(labels, code)
  end

  defp parse(%{code: code, declarations: declarations}) do
    {variables, address, errors} = Compiler.Declarations.prepare_variable_map(declarations)
    Compiler.Code.gen_assembly(code, {variables, %{}, address, errors}, "")
  end

end
