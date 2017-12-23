Nonterminals input declarations declaration code line variable value expression.
Terminals 'VAR' 'BEGIN' 'END' '\n' identifier number '[' ']' ' ' ':=' ';'.
Rootsymbol input.

input -> 'VAR' '\n' declarations '\n' 'BEGIN' '\n' code 'END': #{declarations => '$3', code => '$7'}.

% '\n' 'BEGIN' '\n' code '\n' 'END'

declaration -> identifier'['number']' : {array, extract_value('$1'), list_to_integer(extract_value('$3'))}.
declaration -> identifier : {var, extract_value('$1')}.

declarations -> declaration : ['$1'].
declarations -> declaration ' ' declarations : ['$1' | '$3'].

code -> line '\n' : ['$1'].
code -> line '\n' code : ['$1' | '$3'].

line -> variable ' ' ':=' ' ' expression';' : {assign, '$1', '$5'}.

expression -> value : '$1'.

value -> number : {number, list_to_integer(extract_value('$1'))}.
value -> variable : '$1'.

variable -> identifier : {var, extract_value('$1')}.
variable -> identifier'['number']' : {array, extract_value('$1'), number, list_to_integer(extract_value('$3'))}.
variable -> identifier'['identifier']' : {array, extract_value('$1'), var, extract_value('$3')}.


Erlang code.
extract_value({_Token, _Line, Value}) -> Value.
