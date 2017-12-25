Nonterminals input declarations declaration code cmd variable value expression.
Terminals VAR BEGIN END '\n' identifier number '[' ']' ' ' ':=' ';' '+'.
Rootsymbol input.

input -> VAR declarations BEGIN code END: #{declarations => '$2', code => '$4'}.

% '\n' 'BEGIN' '\n' code '\n' 'END'

declaration -> identifier'['number']' : {array, extract_value('$1'), list_to_integer(extract_value('$3')), declaration_line_number('$1')}.
declaration -> identifier : {var, extract_value('$1'), declaration_line_number('$1')}.

declarations -> declaration : ['$1'].
declarations -> declaration declarations : ['$1' | '$2'].

code -> cmd : ['$1'].
code -> cmd code : ['$1' | '$2'].

cmd -> variable ':=' expression';' : {line_number('$2'), assign, {'$1', '$3'}}.

expression -> value : '$1'.
expression -> value '+' value : {add, '$1', '$3'} .

value -> number : {number, list_to_integer(extract_value('$1'))}.
value -> variable : '$1'.

variable -> identifier : {var, extract_value('$1')}.
variable -> identifier'['number']' : {array, extract_value('$1'), number, list_to_integer(extract_value('$3'))}.
variable -> identifier'['identifier']' : {array, extract_value('$1'), var, extract_value('$3')}.


Erlang code.
extract_value({_Token, _Line, Value}) -> Value.
line_number({_Token, Line}) -> Line.
declaration_line_number({_Token, Line, _Value}) -> Line.
