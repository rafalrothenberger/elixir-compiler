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
    a = Compiler.Declarations.prepare_variable_map(declarations)
    IO.inspect(a)
    {variables, address, errors} = a
    a = Compiler.Code.gen_assembly(code, {variables, %{}, address, errors}, "")
    IO.inspect(a)
  end



end
