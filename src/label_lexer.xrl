Definitions.

LABEL       = ![^!]*!
ANY         = .
NEWLINE     = '\n'

Rules.

\n                                          : skip_token.
{LABEL}                                     : {token, {TokenChars, TokenLine - 1}}.
.                                           : skip_token.

Erlang code.
