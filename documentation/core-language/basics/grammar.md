+++
title = "Source grammar"
weight = 6
+++

# Source grammar

Exact syntax reference. New to the language? Start with [source files](syntax.md). Parsing checks shape only; [expression rules](expressions.md) and [type rules](../types/compatibility.md) decide legality.

## Source characters and tokens

- Source is UTF-8 without a byte-order mark. CRLF is normalized to LF; a lone CR is rejected everywhere, comments included.
- Bidirectional text controls (U+202A to U+202E and U+2066 to U+2069) are rejected in comments and text, since they can make source display differently from how it is read; write `\u{202E}` in text when the character is needed.
- Identifiers are `[A-Za-z_][A-Za-z0-9_]*` and case-sensitive. A lone `_` is a pattern placeholder. Unicode is allowed in text and comments only.

The language uses these keywords:

```manuscript
and break continue else enum export extern false fixture fn for if
impl import in interface match not or return self test true try type
unit var while
```

- Most keywords are reserved only where they mean something. After `.`, and as a `name:` label that starts a line or follows `(` or `,` (a record or enum field, a parameter, an argument label), these are ordinary names: `break continue enum export extern fixture for if impl import in interface match ref return test type while`. So `type Options:` can declare `continue: Bool` and `if: Int`, `Options(continue: true)` sets it, and `opts.continue` reads it. A binding or function still cannot use these words, and `and`, `or`, `not`, `else`, `fn`, `try`, `var`, `self`, `unit`, `true` and `false` stay reserved everywhere.
- `try` is reserved only to report that it was replaced: write a postfix `?` (`f(x)?`) to propagate a Result error.
- `opaque` is contextual: it modifies a `type` declaration only directly before `type` (`export opaque type Name:`), so `opaque := 1` is valid.
- `from` ends an import's names and `bench` starts a benchmark only before a string literal at a module item; both are contextual, so `from := 2` and `bench := 3` are valid.
- Words from other languages (`def`, `lambda`, `elif`, `True`, `False`, `None`, `class`, `except`, `raise`, `finally`, `async`, `await`, `yield`, `global`, `nonlocal`, `del`, `is`, `pass`, `throw`, `catch`, `null`, `undefined`, `new`, `this`, `function`) and Python spellings (`f"..."`, `from "p" import x`, `Callable[[Int], Int]`, `a if c else b`, `case` arms, `()` for Unit) are not syntax and get a targeted diagnostic naming the Manuscript form (`fn`, `else if`, `true`, `none`, `unit`, `try expr`, and so on).
- `fixture` names the file fixture inside test blocks when a local `make_fixture` factory returns a concrete `TestHooks` implementer. `fixture` and `self` (the implementation receiver) cannot be declared as parameters or bindings.
- Built-in type names and alternative constructors are not keywords.
- `//` starts a comment through the end of the line. `/* ... */` is a block comment: it starts its own line (after indentation), ends at the first `*/`, and only blanks or a `//` comment may follow the `*/`. Block comments do not nest (a `/*` inside one is an error), an unterminated block is an error at its opening `/*`, and the block counts as comment-only lines for layout, so its contents are free-form. `#` is not syntax.
- A tab is allowed only as leading indentation, where it is one level (four columns); a tab after spaces or between tokens is rejected. Tabs are allowed in text and comments. Control characters in text are rejected; use [text escapes](text-and-bytes.md#string-literals). Semicolons and backslash continuation are rejected.

Numeric tokens:

```ebnf
Digit         = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ;
NonzeroDigit  = "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ;
Digits        = Digit, { [ "_" ], Digit } ;
Whole         = "0" | NonzeroDigit, { [ "_" ], Digit } ;
Fraction      = ".", Digits ;
Exponent      = ("e" | "E"), [ "+" | "-" ], Digit, { Digit } ;
HexLiteral    = "0x", HexDigit, { [ "_" ], HexDigit } ;
BinLiteral    = "0b", ( "0" | "1" ), { [ "_" ], ( "0" | "1" ) } ;
IntLiteral    = Whole | HexLiteral | BinLiteral ;
FloatLiteral  = Whole, (Fraction, [ Exponent ] | Exponent) ;
DecimalLiteral = Whole, [ Fraction ], [ Exponent ], "d" ;
```

`HexDigit` is `0`-`9`, `a`-`f` or `A`-`F`. `_` sits between two digits of an integer or of a fraction, never leading, trailing, doubled or beside the prefix, `.`, `e` or `d`; the exponent takes none.

No identifier character may follow a numeric token except the `d` suffix. Leading zeros, octal (`0o`), uppercase prefixes (`0X`, `0B`), `.5`, and `1.` are rejected. `1e3` is a Float. A sign is an operator, not part of the token ([range checking](numbers-and-booleans.md)). A dot starts a fraction only before a digit, so `2.seconds()` is an Int, a dot, and a method name.

## Layout tokens

- Module-level code starts in column zero. `:` introduces a suite: one simple statement inline, or a nonempty indented block.
- An indented suite's first line is exactly four spaces deeper than its header; siblings match it, and a dedent must return to an enclosing indentation. Blank and comment-only lines are ignored.
- The grammar's `NEWLINE`, `INDENT`, and `DEDENT` mark these boundaries; end of file closes open suites. There is no `pass`; a suite cannot be empty, except that `...` stands for a runtime-bound body or a schema with no fields (see below).
- Inside `()`, `[]`, `{}`, newlines are suppressed and continuation lines indent in multiples of four.
- A line starting with `|`, or `.` not followed by a digit or `.`, continues the previous statement, indented exactly four spaces past it ([pipe flows](expressions.md#pipe-flows)).
- Delimiters must balance; a closer may align with its opener's line. Trailing commas are allowed only in comma-separated forms below.

### Anonymous-function suites inside delimiters

Inside a call, list, or grouping, a function expression may have an inline suite (ending at the enclosing comma or closer) or an indented suite, which is the exception to newline suppression. At the header's `:`:

1. Record the delimiter depth and the line's leading indentation (not the column of `fn`).
2. The next significant line must add exactly four spaces.
3. Apply normal statement newlines and indentation at that depth; delimiters opened in the body still suppress newlines.
4. The suite ends when a line returns to the header indentation or less; then the surrounding delimiter rules resume.

A delimiter opened outside the body cannot close at body indentation. Group the function when a following comma belongs to the enclosing arguments:

```manuscript
fn example() Int:
    return apply(
        value: 3,
        transform: (
            fn(value: Int) Int:
                return value - 1
        ),
    )
```

The grouping close (eight spaces) ends the function suite before the comma. An ungrouped suite-bodied function can be the final argument:

```manuscript
fn example() Int:
    return apply(
        value: 3,
        transform: fn(value: Int) Int:
            return value - 1
    )
```

Use `fn value: value - 1` when context supplies the parameter type; an inline body returns its value (it can be a conditional expression: `fn value: if value > 0: value else: 0`), while indented bodies use explicit returns. To add another argument after an ungrouped indented function, put the comma on its own line at the header's indentation:

```manuscript
fn example() Int:
    return apply(
        transform: fn(value: Int) Int:
            return value - 1
        ,
        value: 3,
    )
```

A comma after `return value - 1` stays in the body and is rejected. Grouping the function also allows `),` before another argument.

## Modules, declarations, and types

In the EBNF, braces repeat, brackets are optional, and quoted brackets are source tokens. `StringLiteral` is defined in [text and bytes](text-and-bytes.md), `Expression` in [expressions](expressions.md).

```ebnf
Module        = { Import | Declaration } ;
Import        = "import", ( ImportNames | "(", ImportNames, [ "," ], ")" ), "from", PlainStringLiteral, NEWLINE ;
ImportNames   = Name, { ",", Name } ;
Declaration   = [ "export" ], (TypeDeclaration | EnumDeclaration | InterfaceDeclaration | FunctionDeclaration
              | ConstantDeclaration | ExternDeclaration)
              | Implementation | TestDeclaration | BenchDeclaration ;
ConstantDeclaration = Name, ( ":=", Expression | ":", Type, ":=", Expression ), NEWLINE ;

TypeDeclaration = [ "opaque" ], "type", Name, [ TypeParameters ], ":",
                  ("...", NEWLINE | NEWLINE, INDENT, RecordBody, DEDENT) ;
EnumDeclaration = [ "opaque" ], "enum", Name, [ TypeParameters ], ":", NEWLINE,
                  INDENT, AlternativeBody, DEDENT ;
RecordBody    = { Field } ;
Field         = Name, ":", Type, [ "=", Expression ], NEWLINE ;
AlternativeBody = VariantDeclaration, { VariantDeclaration } ;
VariantDeclaration = Name, [ "(", Parameters, ")" ], NEWLINE ;
InterfaceDeclaration = "interface", Name, [ TypeParameters ], ":",
                       ("...", NEWLINE | NEWLINE, INDENT, ContractBody, DEDENT) ;
ContractBody  = OperationSignature, { OperationSignature } ;
OperationSignature = [ "var" ], "fn", Name, [ TypeParameters ], "(", [ FunctionParameters ], ")", ResultType, NEWLINE ;
FunctionDeclaration = "fn", Name, [ TypeParameters ], "(", [ FunctionParameters ], ")",
                      ResultType, FunctionSuite ;
ResultType    = Type ;
Implementation = "impl", NamedType, [ "for", NamedType ], ":", NEWLINE,
                 [ INDENT, MethodDeclaration, { MethodDeclaration }, DEDENT ] ;
(* With "for", the first NamedType is the interface and the second the type. Without it, the only NamedType is the type and the block declares its own methods. *)
MethodDeclaration = [ "var" ], "fn", Name, [ TypeParameters ], "(", [ FunctionParameters ], ")", ResultType, FunctionSuite ;
ExternDeclaration = "extern", "fn", Name, "(", [ FunctionParameters ], ")", ResultType, NEWLINE
                  | "extern", "type", Name, [ TypeParameters ], NEWLINE ;
FunctionSuite = ":", ("...", NEWLINE | Expression | SimpleStatement | NEWLINE, INDENT, { Statement }, DEDENT) ;
TestDeclaration = "test", PlainStringLiteral, Suite ;
(* A test body behaves as if it returns Result[Unit, Error]: completing, bare return, or `return unit` succeeds; a postfix `?` or return error(...) fails it. *)
(* Only canonical TestHooks implementations may omit operations; missing hooks are no-ops. *)
BenchDeclaration = "bench", PlainStringLiteral, [ "per", PositiveInteger ], Suite ;
(* `bench` is contextual: it starts a declaration only before a string literal. The body is one iteration (`per N` says it performs N operations, and `ms bench` then reports per operation), with a test body's result rules and no `fixture`; `ms bench` repeats and times it. *)
Parameters    = Parameter, { ",", Parameter }, [ "," ] ;
Parameter     = Name, ":", Type ;
FunctionParameters = FunctionParameter, { ",", FunctionParameter }, [ "," ] ;
FunctionParameter = [ "var" ], Parameter, [ "=", Expression ] ;
CallbackParameters = CallbackParameter, { ",", CallbackParameter }, [ "," ] ;
CallbackParameter = [ "var" ], Name, [ ":", Type ], [ "=", Expression ] ;
TypeParameters = "[", TypeParameter, { ",", TypeParameter }, [ "," ], "]" ;
TypeParameter = Name, [ ":", Bounds ], [ "=", Type ] ;
Bounds        = NamedType, { "&", NamedType } ;

Type          = ( NamedType | FunctionType | "(", Type, ")" ), { "?" | "!", [ NamedType ] } ;
NamedType     = TypePath, [ TypeArguments ] ;
TypePath      = Name, { ".", Name } ;
TypeArguments = "[", Type, { ",", Type }, [ "," ], "]" ;
FunctionType  = "fn", "(", [ [ "var" ], Type, { ",", [ "var" ], Type } ], ")", Type ;
```

- A type suffix `?` is `Optional[T]`; `!` is `Result[T, Error]`, and `!E` with `E` directly after the bang is `Result[T, E]`. Suffixes apply left to right.
- A `type` declares record fields; an `enum` declares one or more variants. Their methods go in an `impl` block, `impl Type:` for its own or `impl Interface for Type:` for an interface. An `interface` holds only operation signatures. A payloadless variant is `Ready`, without `()`. Names are unique per scope.
- A result type follows the parameter list with no arrow (`fn double(value: Int) Int:`); `->` is rejected with the remedy. An anonymous `fn` writes parameters without parentheses when none is typed (`fn value: value * 2`), and with parentheses when it types a parameter or declares a result (`fn(value: Int) Int: value * 2`).
- Named functions (`fn`) need explicit parameter and result types; anonymous ones may infer them ([callback inference](../functions/function-values-and-closures.md#contextual-callback-inference)).
- Defaults: [function parameters](../functions/declarations-and-calls.md#default-arguments), [record fields](../types/named-types.md#construction), and `= none` on Optional interface parameters. Function types and enum payloads have none. Parameter names in a function type do not exist: two function types are the same when their parameter types, `var` markers and result type match, and calls through function values are positional. No variadics or parameter patterns.
- A named function or method body may be `...` (`fn read_bytes(count: Int) Bytes: ...`), as may a type schema (`type Duration: ...`); the standard library uses this for runtime-bound implementations. In the standard library, a property interface uses `interface Name: ...`; an empty implementation may supply a marker interface. Test, bench, and control-flow suites are nonempty.
- Imports and declarations may interleave; order does not affect resolution. Import paths, test names, and bench names are plain literals (escapes allowed, no interpolation).
- `export` applies to records, enums, interfaces, named functions, constants and extern declarations, not tests, benches, or `impl` blocks.
- `impl` blocks declare no type parameters, and `impl Type:` is accepted only in the module that declares `Type`: in `impl Contract[T] for Data[T]:`, `T` comes from the receiver type and bounds from the declarations. Receiver parameters must occur in the receiver application. Operations and source methods may also declare their own [type parameters](../types/contracts.md#generic-operations). Overlap follows [contracts](../types/contracts.md#generic-implementations).
- `&` only combines generic bounds, as in `T: Read & Closeable`; order is irrelevant. There is no intersection or refinement syntax for value types.
- No module-level statements or `var`; a top-level `:=` is a [constant](../modules/declarations.md#constants). Snippets of local bindings are body fragments. Type paths add no wildcard imports; see [module rules](../modules/declarations.md).

## Statements and patterns

```ebnf
Suite         = ":", (SimpleStatement | NEWLINE, INDENT, Statement, { Statement }, DEDENT) ;
Statement     = SimpleStatement, NEWLINE
              | IfStatement | WhileStatement | ForStatement ;
SimpleStatement = Binding | Assignment | CompoundAssignment | ReturnStatement | "break" | "continue"
                | CallStatement ;
Binding       = ImmutableBinding | "var", ( VarEntry
              | "(", NEWLINE, { VarEntry, NEWLINE }, ")" ) ;
ImmutableBinding = ( Name | PositionalPattern | RecordPattern ), ":=", Expression
              | Name, ":", Type, ":=", Expression ;
VarEntry      = (Name, [ ":", Type ] | PositionalPattern | RecordPattern), "=", Expression ;
Assignment    = AssignmentTarget, "=", Expression ;
AssignmentTarget = Name, { ".", Name | "[", Expression, "]" } ;
CompoundAssignment = AssignmentTarget, ( "+=" | "-=" | "*=" | "/=" | "%=" ), Expression ;
ReturnStatement = "return", [ Expression ] ;
CallStatement = Expression ;
IfStatement   = "if", [ Name, ":=" | "var", Name, "=" ], Expression, Suite,
                { "else", "if", [ Name, ":=" | "var", Name, "=" ], Expression, Suite },
                [ "else", Suite ] ;
WhileStatement = "while", Expression, Suite ;
ForStatement  = "for", Name, "in", Expression, Suite ;
MatchExpression = "match", Expression, ":", NEWLINE, INDENT,
                 MatchArm, { MatchArm }, DEDENT ;
MatchArm      = (CasePattern | LiteralPattern | "_"), ArmSuite ;
LiteralPattern = [ "-" ], Number | String | "true" | "false" ;
ArmSuite      = ":", (SimpleStatement | Expression
              | NEWLINE, INDENT, { Statement }, [ Expression, NEWLINE ], DEDENT) ;
CasePattern   = CasePath, [ "(", PayloadNames, ")" ] ;
CasePath      = Name, [ TypeArguments ], { ".", Name } ;
PayloadNames  = (Name | "_"), { ",", (Name | "_") }, [ "," ] ;

BindingPattern = Name | PositionalPattern | RecordPattern ;
PositionalPattern = "[", [ BindingPattern, { ",", BindingPattern }, [ "," ] ], "]" ;
RecordPattern = "{", RecordEntry, { ",", RecordEntry }, [ "," ], "}" ;
RecordEntry   = Name, [ ":", BindingPattern ] ;
```

- `CallStatement` accepts a call or match and discards the result, or `call()?` when the success type is `Unit` ([propagation](../errors/propagation.md)). Bare names and arithmetic are not statements.
- Assignment replaces a `var` or record field. `target op= value` means `target = target op (value)`; write the operator and `=` adjacent. The target is mutable storage: a name, field path (`box.inner.count += 1`), list index (`values[i] += 1`), or map entry (`stock[line.sku] -= line.qty`). The index of a compound target is a name, field path or literal, so it is read twice without effect; the store takes a clone of the key and the name stays usable. Calls cannot be assignment targets. `+=` appends text; `-=` on text is an error.
- Only a simple name takes a type annotation. Positional patterns may be empty; empty record patterns are rejected. `_` discards a binding or match payload and is the wildcard match arm; it cannot be read as a value.
- Inline suites (functions, methods, tests, branches, loops) hold one simple statement, no nested compound statements. Functions and methods alone may hold one expression, which is returned:

```manuscript
fn double(value: Int) Int: value * 2
fn positive(value: Int) Bool:
    if value > 0: return true
    else: return false
```

- `else if` and `else` start on their own line at the `if` header's indentation; inline and indented branches may mix.
- A match arm holds one statement or value inline, or statements then a value when indented.
- Match patterns use positional payloads, not labels. On a contract view, a pattern names a complete concrete type and one receiver binding, with a final wildcard ([pattern matching](../control-flow/pattern-matching.md)).
- `match` is an expression even when discarded; loops are statements, and `if` is a statement. The conditional expression is `if c: a else: b` (a required `else:`; chains continue with `else if`). An inline function body that starts with one is parenthesized: `fn x: (if x > 0: 1 else: 0)`.
- Local type, implementation, import, test, and bench declarations are rejected; a local function is a `fn` statement, sugar for binding a `fn` (it cannot call itself).
- Resources follow the [scope-end cleanup](../cleanup/scopes.md) contract. There is no move, borrow, spawn, or deferred-call syntax.

## Rejected forms

```manuscript
count := 3                       // Not a complete module item.
fn wrong() Int:
  return 1                          // A suite requires four spaces.
fn wrong() Int:
    (first, second) := pair          // Parentheses are not a binding pattern.
```

Each example is an independent rejected form.

## Nesting limits

The parser rejects nesting deeper than 1000 levels (expressions, types, patterns, blocks, interpolated literals) and chains longer than 10000 operators, member accesses, calls, or indexes, reporting `parse: nesting exceeds 1000 levels`.

[Back to language basics](_index.md) · [Expressions and operators](expressions.md)
