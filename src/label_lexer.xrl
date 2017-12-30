Definitions.

LABEL       = ![^!]*!
ANY         = .
NEWLINE     = '\n'

Rules.

\n                                          : skip_token.
{LABEL}                                     : {token, {get_label(TokenChars), TokenLine - 1}}.
.                                           : skip_token.

Erlang code.
% get_label(str) -> string:trim(lists:join('', str), both, '!').
get_label(Str) -> string:trim(Str, both, "!").
% get_label(Str) -> Str.
