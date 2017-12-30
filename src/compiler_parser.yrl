Nonterminals input declarations declaration code cmd variable value expression condition.
Terminals VAR BEGIN END READ WRITE IF THEN ELSE ENDIF WHILE DO ENDWHILE FOR FROM DOWNTO TO ENDFOR'\n' identifier number '[' ']' ' ' ':=' ';' '+' '-' '*' '/' '%' '=' '<' '>' '<=' '>=' '<>'.
Rootsymbol input.

input -> VAR declarations BEGIN code END: #{declarations => '$2', code => '$4'}.
input -> VAR declarations BEGIN END: #{declarations => '$2', code => []}.
input -> VAR BEGIN code END: #{declarations => [], code => '$3'}.
input -> VAR BEGIN END: #{declarations => [], code => []}.

% '\n' 'BEGIN' '\n' code '\n' 'END'

declaration -> identifier'['number']' : {array, extract_value('$1'), list_to_integer(extract_value('$3')), declaration_line_number('$1')}.
declaration -> identifier : {var, extract_value('$1'), declaration_line_number('$1')}.

declarations -> declaration : ['$1'].
declarations -> declaration declarations : ['$1' | '$2'].

code -> cmd : ['$1'].
code -> cmd code : ['$1' | '$2'].

cmd -> variable ':=' expression';' : {line_number('$2'), assign, {'$1', '$3'}}.
cmd -> IF condition THEN code ELSE code ENDIF : {line_number('$1'), ifelse, {'$2', '$4', '$6'}}.
cmd -> IF condition THEN code ENDIF : {line_number('$1'), ifonly, {'$2', '$4'}}.
cmd -> WHILE condition DO code ENDWHILE : {line_number('$1'), while, {'$2', '$4'}}.
cmd -> FOR identifier FROM value DOWNTO value DO code ENDFOR : {line_number('$1'), for, {get_identifier_name('$2'), '$4', '$6', '$8', downto}}.
cmd -> FOR identifier FROM value TO value DO code ENDFOR : {line_number('$1'), for, {get_identifier_name('$2'), '$4', '$6', '$8', to}}.
cmd -> READ variable ';': {line_number('$1'), read, {'$2'}}.
cmd -> WRITE value ';': {line_number('$1'), write, {'$2'}}.

expression -> value : '$1'.
expression -> value '+' value : {add, '$1', '$3'} .
expression -> value '-' value : {sub, '$1', '$3'} .
expression -> value '*' value : {multiply, '$1', '$3'} .
expression -> value '/' value : {divide, '$1', '$3'} .
expression -> value '%' value : {mod, '$1', '$3'} .

condition -> value '=' value : {equals, '$1', '$3'}.
condition -> value '<>' value : {ne, '$1', '$3'}.
condition -> value '<' value : {l, '$1', '$3'}.
condition -> value '<=' value : {le, '$1', '$3'}.
condition -> value '>' value : {g, '$1', '$3'}.
condition -> value '>=' value : {ge, '$1', '$3'}.

value -> number : {number, {list_to_integer(extract_value('$1'))}}.
value -> variable : '$1'.

variable -> identifier : {var, extract_value('$1'), {}}.
variable -> identifier'['number']' : {array, extract_value('$1'), {number, list_to_integer(extract_value('$3'))}}.
variable -> identifier'['identifier']' : {array, extract_value('$1'), {var, extract_value('$3')}}.


Erlang code.
extract_value({_Token, _Line, Value}) -> Value.
line_number({_Token, Line}) -> Line.
declaration_line_number({_Token, Line, _Value}) -> Line.
get_identifier_name({_A, _B, Name}) -> Name.
