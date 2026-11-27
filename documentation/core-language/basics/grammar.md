+++
title = "Source grammar"
weight = 6
+++

# Source grammar

This page is the exact syntax reference. New to the language? Start with [source files](syntax.md). Parsing checks shape only; [expression rules](expressions.md) and [type rules](../types/compatibility.md) decide legality.

## Source characters and tokens

- Source is UTF-8 without a byte-order mark. CRLF is normalized to LF; a lone CR is rejected everywhere, comments included.
- Bidirectional text controls (U+202A to U+202E and U+2066 to U+2069) are rejected in comments and text, since they can make source display differently from how it is read; write `\u{202E}` in text when the character is needed.
- Identifiers are `[A-Za-z_][A-Za-z0-9_]*` and case-sensitive. A lone `_` is a pattern placeholder. Unicode is allowed in text and comments only.

The language uses these keywords:

```text
and break continue else enum export extern false fixture fn for if
import in interface match not or return self test true type
void var while
```

- Most keywords are reserved only where they mean something. After `.`, and as a `name:` label that starts a line or follows `(` or `,` (a record or enum field, a parameter, an argument label), these are ordinary names: `break continue enum export extern fixture for if import in interface match return test type while`.
- So `type Options { ... }` can declare `continue Bool` and `if Int`, `Options(continue: true)` sets it, and `opts.continue` reads it. A binding or function still cannot use these words. `and`, `or`, `not`, `else`, `fn`, `var`, `self`, `void`, `true` and `false` stay reserved everywhere.
- `try` and `impl` are not keywords. Writing the old `try f(x)` or an `impl` block reports the replacement: a postfix `?` (`f(x)?`) propagates a Result error, and `fn Type.name(...)` declares a method.
- `opaque` is contextual: it modifies a `type` declaration only directly before `type` (`export opaque type Name { ... }`), so `opaque := 1` is valid.
- `from` ends an import's names and `bench` starts a benchmark only before a string literal at a module item; both are contextual, so `from := 2` and `bench := 3` are valid.
- Words from other languages (`def`, `lambda`, `elif`, `True`, `False`, `None`, `class`, `except`, `raise`, `finally`, `async`, `await`, `yield`, `global`, `nonlocal`, `del`, `is`, `pass`, `throw`, `catch`, `null`, `undefined`, `new`, `this`, `function`) and Python spellings (`f"..."`, `from "p" import x`, `Callable[[Int], Int]`, `a if c else b`, `case` arms, `()` for Void) are not syntax and get a targeted diagnostic naming the Manuscript form (`fn`, `else if`, `true`, `null`, `void`, `try expr`, and so on).
- `fixture` names the file fixture inside test blocks when a local `make_fixture` factory returns a concrete `TestHooks` implementer. `fixture` and `self` (the implementation receiver) cannot be declared as parameters or bindings.
- Built-in type names and alternative constructors are not keywords.
- `//` starts a comment through the end of the line. `#` is not syntax.
- `/* ... */` is a block comment. It starts its own line (after indentation), ends at the first `*/`, and only blanks or a `//` comment may follow the `*/`. Block comments do not nest (a `/*` inside one is an error), and an unterminated block is an error at its opening `/*`. The block counts as comment-only lines for layout, so its contents are free-form.
- A tab is allowed only in a line's leading whitespace (four columns), never between tokens. Tabs are allowed in text and comments. Control characters in text are rejected; use [text escapes](text-and-bytes.md#string-literals). Semicolons and backslash continuation are rejected.

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

## Blocks and line ends

- A block is `{`, statements, `}`. Every compound statement and every declaration body uses one, even for a single line: `if c { return 1 }`. A block is never empty, except that `...` stands for a runtime-bound body or a schema with no fields (see below). There is no `pass`.
- A statement ends at the end of its line, or at the `}` that closes its block. Inside `()`, `[]` and a map's `{}`, newlines are suppressed. `;` and backslash continuation are rejected.
- Indentation carries no meaning. [`ms fmt`](../../developer-tooling/source/formatting.md) indents each block four spaces (a tab per level on disk) and puts `{` at the end of the header line and `}` at the start of its own line. A block that fits on one line may stay on it.
- `else` follows the closing brace on the same line: `} else {` and `} else if c {`. A line that starts with `else` after a `}` line is accepted and joined by the formatter.
- A line starting with `|`, or `.` not followed by a digit or `.`, continues the previous statement ([pipe flows](expressions.md#pipe-flows)).
- A `{` opens a block unless it follows a token that expects an operand (`(`, `[`, `,`, `=`, `:=`, `:`, `return`, an operator, `in`) or its matching `}` is followed by `:=` or `=`; there it is a [map literal](../types/collections.md#map-literals) or a destructuring pattern. `=> {` is always a block, so a map returned from an arrow body is written in parentheses: `() => ({"a": 1})`. A bare `{ ... }` statement is a scope.
- Delimiters must balance. Trailing commas are allowed only in comma-separated forms below.

### Anonymous functions inside delimiters

Inside a call, list, or grouping, a function expression may have a `=>` body (ending at the enclosing comma or closer) or a block body. A block body is delimited by its braces, so a following comma belongs to the enclosing arguments:

<!-- manuscript-example: {"mode":"fragment","context":"fn apply(value Int, transform fn(Int) Int) Int {\n    return transform(value)\n}","given":[]} -->
```manuscript
fn offset() Int {
    return apply(
        transform: fn(value Int) Int {
            return value - 1
        },
        value: 3,
    )
}
```

Use `value => value - 1` when context supplies the parameter type; a `=>` body is one expression and returns its value (it can be a conditional expression: `value => if value > 0 { value } else { 0 }`). A longer body goes in braces after `=>` (`value => { ... }`, with explicit returns) or after the signature of a typed closure (`fn(value Int) Int { ... }`).

## Modules, declarations, and types

In the EBNF, braces repeat, brackets are optional, and quoted brackets are source tokens. `StringLiteral` is defined in [text and bytes](text-and-bytes.md), `Expression` in [expressions](expressions.md).

```ebnf
Module        = { Import | Declaration } ;
Import        = "import", ( ImportNames | "(", ImportNames, [ "," ], ")" ), "from", PlainStringLiteral, NEWLINE ;
ImportNames   = Name, { ",", Name } ;
Declaration   = [ "export" ], (TypeDeclaration | AliasDeclaration | EnumDeclaration | InterfaceDeclaration | FunctionDeclaration
              | ConstantDeclaration | ExternDeclaration)
              | Implementation | TestDeclaration | BenchDeclaration ;
ConstantDeclaration = Name, ( ":=", Expression | Type, ":=", Expression ), NEWLINE ;

TypeDeclaration = [ "opaque" ], "type", Name, [ TypeParameters ], "{", ( "...", "}" | RecordBody, "}" ) ;
AliasDeclaration = "type", Name, [ TypeParameters ], "=", Type, { "|", Type }, NEWLINE ;
EnumDeclaration = [ "opaque" ], "enum", Name, [ TypeParameters ], "{", AlternativeBody, "}" ;
RecordBody    = { Field } ;
Field         = Name, { ",", Name }, Type, [ "=", Expression ], NEWLINE ;
AlternativeBody = VariantDeclaration, { VariantDeclaration } ;
VariantDeclaration = Name, [ "(", Parameters, ")" ], NEWLINE ;
InterfaceDeclaration = "interface", Name, [ TypeParameters ], "{", ( "...", "}" | ContractBody, "}" ) ;
ContractBody  = OperationSignature, { OperationSignature } ;
OperationSignature = [ "var" ], "fn", Name, [ TypeParameters ], "(", [ FunctionParameters ], ")", ResultType, NEWLINE ;
FunctionDeclaration = "fn", Name, [ TypeParameters ], "(", [ FunctionParameters ], ")",
                      ResultType, FunctionSuite ;
ResultType    = Type ;
MethodDeclaration = "fn", [ "var" ], Receiver, ".", Name, [ TypeParameters ], "(", [ FunctionParameters ], ")",
                    ResultType, FunctionSuite ;
Receiver      = Name, [ "[", ReceiverArgument, { ",", ReceiverArgument }, "]" ] ;
ReceiverArgument = Name, [ Bound ] | Type ;
(* The receiver names the declared type, with one argument per type parameter: its name, optionally bounded, or a concrete type. *)
ExternDeclaration = "extern", "fn", Name, "(", [ FunctionParameters ], ")", ResultType, NEWLINE
                  | "extern", "type", Name, [ TypeParameters ], NEWLINE ;
FunctionSuite = "=>", (Expression | SimpleStatement)
              | "{", ( "...", "}" | Statement, { Statement }, "}" ) ;
ArrowFunction = (Name | "(", [ ParameterNames ], ")"), "=>", (Expression | SimpleStatement) ;
ParameterNames = ParameterName, { ",", ParameterName } ;
ParameterName = [ "var" | "move" ], Name | Pattern ;
TestDeclaration = "test", PlainStringLiteral, Block ;
(* A test body behaves as if it returns Result[Void, Error]: completing, bare return, or `return` succeeds; a postfix `?` or return error(...) fails it. *)
(* Only canonical TestHooks implementations may omit operations; missing hooks are no-ops. *)
BenchDeclaration = "bench", PlainStringLiteral, [ "per", PositiveInteger ], Block ;
(* `bench` is contextual: it starts a declaration only before a string literal. The body is one iteration (`per N` says it performs N operations, and `ms bench` then reports per operation), with a test body's result rules and no `fixture`; `ms bench` repeats and times it. *)
Parameters    = Parameter, { ",", Parameter }, [ "," ] ;
Parameter     = Name, { ",", Name }, Type ;
(* `width, height Int` declares two names of one type; the default of `FunctionParameter` and `Field` applies to each. *)
FunctionParameters = FunctionParameter, { ",", FunctionParameter }, [ "," ] ;
FunctionParameter = [ "var" ], Parameter, [ "=", Expression ] ;
CallbackParameters = CallbackParameter, { ",", CallbackParameter }, [ "," ] ;
CallbackParameter = [ "var" ], Name, [ Type ], [ "=", Expression ] ;
TypeParameters = "[", TypeParameter, { ",", TypeParameter }, [ "," ], "]" ;
TypeParameter = Name, [ Bounds ], [ "=", Type ] ;
Bounds        = NamedType, { "&", NamedType } ;

Type          = ( NamedType | FunctionType | "(", Type, ")" ), { "?" | "!", [ NamedType ] } ;
NamedType     = TypePath, [ TypeArguments ] ;
TypePath      = Name, { ".", Name } ;
TypeArguments = "[", Type, { ",", Type }, [ "," ], "]" ;
FunctionType  = "fn", "(", [ [ "var" ], Type, { ",", [ "var" ], Type } ], ")", Type ;
```

- A type suffix `?` is `Optional[T]`; `!` is `Result[T, Error]`, and `!E` with `E` directly after the bang is `Result[T, E]`. Suffixes apply left to right.
- A `type Name = Type` declares an [alias](../types/named-types.md#aliases): another name for the same type, or with `|` a [type set](../types/generics.md#type-sets) that bounds a type parameter. A `type Name { ... }` declares record fields; an `enum` declares one or more variants. Their methods are receiver methods, `fn Type.name(...)`, written beside the type; a type satisfies an interface by having methods that match it. An `interface` holds only operation signatures. A payloadless variant is `Ready`, without `()`. Names are unique per scope.
- A result type follows the parameter list with no arrow (`fn double(value Int) Int { ... }`); `->` is rejected with the remedy. An anonymous function with untyped parameters is written `value => value * 2`, `(a, b) => a + b` or `() => 1`; typing a parameter or declaring a result keeps `fn` (`fn(value Int) Int => value * 2`). A longer body goes in braces after `value =>` or after the signature of `fn(value Int) Int`.
- Named functions (`fn`) need explicit parameter and result types; anonymous ones may infer them ([callback inference](../functions/function-values-and-closures.md#contextual-callback-inference)).
- Defaults: [function parameters](../functions/declarations-and-calls.md#default-arguments), [record fields](../types/named-types.md#construction), and `= null` on Optional interface parameters. Function types and enum payloads have none. Parameter names in a function type do not exist: two function types are the same when their parameter types, `var` markers and result type match, and calls through function values are positional. No variadics or parameter patterns.
- A named function or method body may be `...` (`fn read_bytes(count Int) Bytes { ... }`), as may a type schema (`type Duration { ... }`); the standard library uses this for runtime-bound implementations. In the standard library, a property interface uses `interface Name { ... }`; an empty implementation may supply a marker interface. Test, bench, and control-flow blocks are nonempty.
- Imports and declarations may interleave; order does not affect resolution. Import paths, test names, and bench names are plain literals (escapes allowed; plain `"..."` text, never `f"..."`).
- `export` applies to records, aliases, enums, interfaces, named functions, constants and extern declarations, not tests, benches, or methods.
- A receiver method is accepted only in the module that declares its type, and repeats the type's parameters (`fn Box[T].get() T`), optionally bounded (`fn Box[T Equal].same(...)`) or fixed (`fn List[Int].sum()`). Methods may also declare their own [type parameters](../types/contracts.md#generic-operations). Methods of one name on one receiver form are rejected as [contracts](../types/contracts.md#methods) describe.
- `&` only combines generic bounds, as in `T: Read & Closeable`; order is irrelevant. There is no intersection or refinement syntax for value types.
- No module-level statements or `var`; a top-level `:=` is a [constant](../modules/declarations.md#constants). Snippets of local bindings are body fragments. Type paths add no wildcard imports; see [module rules](../modules/declarations.md).

## Statements and patterns

```ebnf
Block         = "{", Statement, { Statement }, "}" ;
(* A statement ends at NEWLINE or at the "}" that closes the block, so `{ return 1 }` is a block of one statement. *)
Statement     = SimpleStatement, NEWLINE
              | IfStatement | WhileStatement | ForStatement ;
SimpleStatement = Binding | Assignment | CompoundAssignment | ReturnStatement | "break" | "continue"
                | CallStatement ;
Binding       = ImmutableBinding | "var", ( VarEntry
              | "(", NEWLINE, { VarEntry, NEWLINE }, ")" ) ;
ImmutableBinding = ( Name | PositionalPattern | RecordPattern ), ":=", Expression
              | Name, Type, ":=", Expression ;
VarEntry      = (Name, [ Type ] | PositionalPattern | RecordPattern), "=", Expression ;
Assignment    = AssignmentTarget, "=", Expression ;
AssignmentTarget = Name, { ".", Name | "[", Expression, "]" } ;
CompoundAssignment = AssignmentTarget, ( "+=" | "-=" | "*=" | "/=" | "%=" ), Expression ;
ReturnStatement = "return", [ Expression ] ;
CallStatement = Expression | "void", Expression ;
IfStatement   = "if", [ Name, ":=" | "var", Name, "=" ], Expression, Block,
                { "else", "if", [ Name, ":=" | "var", Name, "=" ], Expression, Block },
                [ "else", Block ] ;
WhileStatement = "while", Expression, Block ;
ForStatement  = "for", Name, "in", Expression, Block ;
ScopeStatement = Block ;
MatchExpression = "match", Expression, "{", MatchArm, { MatchArm }, "}" ;
MatchArm      = (CasePattern | LiteralPattern | "_"), ArmSuite ;
LiteralPattern = [ "-" ], Number | String | "true" | "false" ;
ArmSuite      = "=>", (SimpleStatement | Expression)
              | "=>", "{", { Statement }, [ Expression ], "}" ;
CasePattern   = CasePath, [ "(", PayloadNames, ")" ] ;
CasePath      = Name, [ TypeArguments ], { ".", Name } ;
PayloadNames  = (Name | "_"), { ",", (Name | "_") }, [ "," ] ;

BindingPattern = Name | PositionalPattern | RecordPattern ;
PositionalPattern = "[", [ BindingPattern, { ",", BindingPattern }, [ "," ] ], "]" ;
RecordPattern = "{", RecordEntry, { ",", RecordEntry }, [ "," ], "}" ;
RecordEntry   = Name, [ ":", BindingPattern ] ;
```

- `void expression` runs the expression and drops its result on purpose; `void` alone is the Void value. `CallStatement` accepts a call or match and discards the result, or `call()?` when the success type is `Void` ([propagation](../errors/propagation.md)). Bare names and arithmetic are not statements.
- Assignment replaces a `var` or record field. `target op= value` means `target = target op (value)`; write the operator and `=` adjacent. The target is mutable storage: a name, field path (`box.inner.count += 1`), list index (`values[i] += 1`), or map entry (`stock[line.sku] -= line.qty`). The index of a compound target is a name, field path or literal, so it is read twice without effect; the store takes a clone of the key and the name stays usable. Calls cannot be assignment targets. `+=` appends text; `-=` on text is an error.
- Only a simple name takes a type annotation. Positional patterns may be empty; empty record patterns are rejected. `_` discards a binding or match payload and is the wildcard match arm; it cannot be read as a value.
- A block may be written on one line, `if c { return 1 }`, and then holds one statement. A one-line function or method body is written `=>` and holds one expression, which is returned:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
fn double(value Int) Int => value * 2

fn positive(value Int) Bool {
    if value > 0 {
        return true
    } else {
        return false
    }
}
```

- `else if` and `else` follow the closing brace on its line: `} else if c {`, `} else {`. One-line and multi-line blocks may mix; `ms fmt` writes every block of a chain the same way.
- A match arm is `pattern => value` (or one statement) on one line, or `pattern => { ... }` with statements and then a value.
- Match patterns use positional payloads, not labels. On a contract view, a pattern names a complete concrete type and one receiver binding, with a final wildcard ([pattern matching](../control-flow/pattern-matching.md)).
- `match` is an expression even when discarded; loops are statements, and `if` is a statement. The conditional expression is `if c { a } else { b }`; the `else` is required and chains continue with `else if`. An arrow body may be one: `x => if x > 0 { 1 } else { 0 }`.
- Local type, implementation, import, test, and bench declarations are rejected; a local function is a `fn` statement, sugar for binding a `fn` (it cannot call itself).
- Resources follow the [scope-end cleanup](../cleanup/scopes.md) contract. There is no borrow, spawn, or deferred-call syntax. The only ownership keyword is `move`, which marks a parameter or receiver the callee takes ([moving into a function](../types/references.md#moving-into-a-function)); the EBNF above omits it.

## Rejected forms

<!-- manuscript-example: {"mode":"error"} -->
```manuscript
count := 3                       // Not a complete module item.
fn wrong() Int:
    return 1                        // A block opens with a brace, not a colon.
fn wrong() Int {
    (first, second) := pair          // Parentheses are not a binding pattern.
}
```

Each example is an independent rejected form.

## Nesting limits

The parser rejects nesting deeper than 1000 levels (expressions, types, patterns, blocks, interpolated literals) and chains longer than 10000 operators, member accesses, calls, or indexes, reporting `parse: nesting exceeds 1000 levels`.

[Back to language basics](_index.md) · [Expressions and operators](expressions.md)
