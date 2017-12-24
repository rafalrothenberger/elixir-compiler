defmodule Compiler do

  def run(filename) do
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
        {:ok, file} = File.open(filename <> ".out", [:write])
        IO.write(file, assembly)
        File.close(file)
      {:error, errors} ->
        IO.inspect(errors)
    end
  end


  defp parse(%{code: code, declarations: declarations}) do
    a = Compiler.Declarations.prepare_variable_map(declarations)
    IO.inspect(a)
    {variables, address, errors} = a
    Compiler.Code.gen_assembly(code, {variables, %{}, address, errors, 0}, "")
  end



end
