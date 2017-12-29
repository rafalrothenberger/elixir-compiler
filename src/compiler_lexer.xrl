Definitions.

WHITESPACE  = [\s\t\n]
ID          = [a-z_]+
NUM         = 0|[1-9][0-9]*
COMMENT     = \([^\)]*\){WHITESPACE}*

Rules.

{WHITESPACE}+                               : skip_token.
% {WHITESPACE}+                               : {token, {' ', TokenLine}}.
{COMMENT}                                   : skip_token.
VAR                                         : {token, {'VAR', TokenLine}}.
BEGIN                                       : {token, {'BEGIN', TokenLine}}.
END                                         : {token, {'END', TokenLine}}.
READ                                        : {token, {'READ', TokenLine}}.
WRITE                                       : {token, {'WRITE', TokenLine}}.
IF                                          : {token, {'IF', TokenLine}}.
THEN                                        : {token, {'THEN', TokenLine}}.
ELSE                                        : {token, {'ELSE', TokenLine}}.
ENDIF                                       : {token, {'ENDIF', TokenLine}}.
{ID}+                                       : {token, {identifier, TokenLine, TokenChars}}.
{NUM}                                       : {token, {number, TokenLine, TokenChars}}.
\[                                          : {token, {'[', TokenLine}}.
\]                                          : {token, {']', TokenLine}}.
\s?\;\s?                                    : {token, {';', TokenLine}}.
\s?\:\=\s?                                  : {token, {':=', TokenLine}}.
\s?\+\s?                                    : {token, {'+', TokenLine}}.
\s?\-\s?                                    : {token, {'-', TokenLine}}.
\s?\*\s?                                    : {token, {'*', TokenLine}}.
\s?\/\s?                                    : {token, {'/', TokenLine}}.
\s?\%\s?                                    : {token, {'%', TokenLine}}.
\s?\=\s?                                    : {token, {'=', TokenLine}}.
\s?\<\>\s?                                  : {token, {'<>', TokenLine}}.
\s?\<\s?                                    : {token, {'<', TokenLine}}.
\s?\>\s?                                    : {token, {'>', TokenLine}}.
\s?\<\=\s?                                  : {token, {'<=', TokenLine}}.
\s?\>\=\s?                                  : {token, {'>=', TokenLine}}.
% {WHITESPACE}*\n{WHITESPACE}*                : {token, {' ', TokenLine}}.
Erlang code.
