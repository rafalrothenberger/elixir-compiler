Definitions.

WHITESPACE  = [\s\t\n]
ID          = [a-z_]+
NUM         = 0|[1-9][0-9]*
COMMENT     = \([^\)]*\){WHITESPACE}*

Rules.

{WHITESPACE}+                               : skip_token.
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
WHILE                                       : {token, {'WHILE', TokenLine}}.
DO                                          : {token, {'DO', TokenLine}}.
ENDWHILE                                    : {token, {'ENDWHILE', TokenLine}}.
TO                                          : {token, {'TO', TokenLine}}.
DOWNTO                                      : {token, {'DOWNTO', TokenLine}}.
FOR                                         : {token, {'FOR', TokenLine}}.
FROM                                        : {token, {'FROM', TokenLine}}.
ENDFOR                                      : {token, {'ENDFOR', TokenLine}}.
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
[A-Z]+                                      : {error, TokenChars}.

Erlang code.
