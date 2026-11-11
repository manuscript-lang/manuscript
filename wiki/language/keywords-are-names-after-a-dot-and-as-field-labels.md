[Wiki](../index.md) › [Language](index.md)

# Keywords are names after a dot and as field labels

Decision (Chinmay, #3511): reserve a keyword only where it means something, instead of adding a `field:` rename. The lexer (`Tok::is_contextual`, `Scanner::names_a_member`) turns `break continue enum export extern fixture for if impl import in interface match ref return test type while` into names after `.` and as a `word:` label that starts a line or follows `(` or `,`. `else`, `fn`, `?`, `var`, `self`, `unit`, `true`, `false`, `and`, `or` and `not` stay reserved everywhere.

Why: `command[T]` binds each flag to a same-named field, so `--continue` needed a field named `continue`.

Failure mode: a parameter named like a contextual keyword lexes as a name too, but cannot be read as a value (`{for}` fails), because bindings keep the full reserved set. Add a word to the set only if no statement or expression can start with `word:`.

Apply when: changing the keyword list, labels, or field syntax.
