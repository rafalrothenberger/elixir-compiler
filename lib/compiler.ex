defmodule Compiler do

  def run(filename) do
    {:ok, file} = File.open(filename, [:read])
    program = IO.read(file, :all) |> String.to_charlist

    a = :compiler_lexer.string(program)
#    IO.inspect(a)

    {:ok, tokens, _} = a
    IO.inspect(tokens)
#    {:ok, res} = :compiler_parser.parse(tokens)
    res = :compiler_parser.parse(tokens)
    IO.inspect(res)
  end

end
