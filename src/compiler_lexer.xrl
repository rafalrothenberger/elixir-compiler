Definitions.

WHITESPACE  = [\s\t]
ID          = [a-z_]+
NUM         = 0|[1-9][0-9]*

Rules.

VAR                                         : {token, {'VAR', TokenLine}}.
BEGIN                                       : {token, {'BEGIN', TokenLine}}.
END                                         : {token, {'END', TokenLine}}.
{ID}+                                       : {token, {identifier, TokenLine, TokenChars}}.
{NUM}                                       : {token, {number, TokenLine, TokenChars}}.
\[                                          : {token, {'[', TokenLine}}.
\]                                          : {token, {']', TokenLine}}.
\;                                          : {token, {';', TokenLine}}.
\:\=                                        : {token, {':=', TokenLine}}.
\+                                          : {token, {'+', TokenLine}}.
\-                                          : {token, {'-', TokenLine}}.
{WHITESPACE}*\n{WHITESPACE}*                : {token, {'\n', TokenLine}}.
{WHITESPACE}+                               : {token, {' ', TokenLine}}.
Erlang code.
