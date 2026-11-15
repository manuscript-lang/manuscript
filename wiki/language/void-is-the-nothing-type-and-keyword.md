[Wiki](../index.md) › [Language](index.md)

# `Void` is the nothing type and the `void` keyword

Decision (Chinmay, 2026-11-15): the type `Unit` is `Void`, with no alias, because agents trip on names they do not expect. The value of `Void` is written `void`, and `void expression` as a statement runs the expression and drops its result, replacing `_ := expression`.

Reason it stays a type underneath: generic code (`Result[Void, Error]`, `Optional[Void]`, a generic return type) needs one uniform "no value" type, or every generic path in the checker and both backends grows a special case. Users should rarely write the value: bare `return` and falling off the end already succeed.

Mechanism: `void` is the keyword token `Tok::Void` and `ExprKind::Void`. `void expression` parses to the same `StmtKind::Bind` of `_` that `_ := expression` used, so the checker, ownership walk and both backends are unchanged; the formatter and parser treat a `Bind` that starts with `void` as having no `:=`. `_ := value` at statement level is a parse error naming `void`. MIR text uses `void` for the type and the constant. "Unit tests" and the enum unit-case blocks (`ms.unit.N`, `unit_blocks`) are different concepts and keep their names.
