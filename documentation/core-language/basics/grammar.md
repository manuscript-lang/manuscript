+++
title = "Source grammar"
weight = 6
+++

# Source grammar

Exact syntax reference. New to the language? Start with [source files](syntax.md). Parsing checks shape only; [expression rules](expressions.md) and [type rules](../types/compatibility.md) decide legality.

## Source characters and tokens

- Source is UTF-8 without a byte-order mark. CRLF is normalized to LF; a lone CR is rejected everywhere, comments included.
- Identifiers are `[A-Za-z_][A-Za-z0-9_]*` and case-sensitive. A lone `_` is a pattern placeholder. Unicode is allowed in text and comments only.

The reserved words are:

```manuscript
and break case continue def elif else export False fixture for if
impl in interface lambda let match not or ref return self test True try type
var while with
```

- `from` starts an import at a module item, `as` appears only in a `with` header, and `bench` starts a benchmark only before a string literal at a module item; all three are contextual, so `let from = 2`, `let as = 1` and `let bench = 3` are valid.
- Words from other languages (`fn`, `class`, `except`, `raise`, `finally`, `async`, `await`, `yield`, `global`, `nonlocal`, `del`, `is`, `pass`, `throw`, `catch`, `null`, `undefined`, `new`, `this`, `function`) are not syntax and get a targeted diagnostic naming the Manuscript form (`def`, `()`, `try expr`, and so on).
- `fixture` names the file fixture inside test blocks when a local `make_fixture` factory returns a concrete `TestHooks` implementer. `fixture` and `self` (the implementation receiver) cannot be declared as parameters or bindings.
- Built-in type names and alternative constructors are not keywords.
- `#` starts a comment through the end of the line.
- Tabs in code are rejected (allowed in comments). Control characters in text are rejected; use [text escapes](text-and-bytes.md#string-literals). Semicolons and backslash continuation are rejected.

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

No identifier character may follow a numeric token except the `d` suffix. Leading zeros, octal (`0o`), uppercase prefixes (`0X`, `0B`), `.5`, and `1.` are rejected. `1e3` is a Float. A sign is an operator, not part of the token ([range checking](numbers-and-booleans.md)). A dot starts a fraction only before a digit, so `2.seconds` is an Int, a dot, and a member.

## Layout tokens

- Module-level code starts in column zero. `:` introduces a suite: one simple statement inline, or a nonempty indented block.
- An indented suite's first line is exactly four spaces deeper than its header; siblings match it, and a dedent must return to an enclosing indentation. Blank and comment-only lines are ignored.
- The grammar's `NEWLINE`, `INDENT`, and `DEDENT` mark these boundaries; end of file closes open suites. There is no `pass`; a suite cannot be empty, except that `...` stands for a runtime-bound body or a schema with no fields (see below).
- Inside `()`, `[]`, `{}`, newlines are suppressed and continuation lines indent in multiples of four.
- A line starting with `|`, or `.` not followed by a digit or `.`, continues the previous statement, indented exactly four spaces past it ([pipe flows](expressions.md#pipe-flows)).
- Delimiters must balance; a closer may align with its opener's line. Trailing commas are allowed only in comma-separated forms below.

### Anonymous-function suites inside delimiters

Inside a call, list, or grouping, a function expression may have an inline suite (ending at the enclosing comma or closer) or an indented suite, which is the exception to newline suppression. At the header's `:`:

1. Record the delimiter depth and the line's leading indentation (not the column of `lambda`).
2. The next significant line must add exactly four spaces.
3. Apply normal statement newlines and indentation at that depth; delimiters opened in the body still suppress newlines.
4. The suite ends when a line returns to the header indentation or less; then the surrounding delimiter rules resume.

A delimiter opened outside the body cannot close at body indentation. Group the function when a following comma belongs to the enclosing arguments:

```manuscript
def example() -> Int:
    return apply(
        value: 3,
        transform: (
            lambda (value: Int) -> Int:
                return value - 1
        ),
    )
```

The grouping close (eight spaces) ends the function suite before the comma. An ungrouped suite-bodied function can be the final argument:

```manuscript
def example() -> Int:
    return apply(
        value: 3,
        transform: lambda (value: Int) -> Int:
            return value - 1
    )
```

Use `lambda value: value - 1` when context supplies the parameter type; an inline body returns its value, while indented bodies use explicit returns. To add another argument after an ungrouped indented function, put the comma on its own line at the header's indentation:

```manuscript
def example() -> Int:
    return apply(
        transform: lambda (value: Int) -> Int:
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
Import        = "from", PlainStringLiteral, "import",
                ( ImportNames, NEWLINE
                | "(", NEWLINE, INDENT, ImportNames, DEDENT, ")", NEWLINE ) ;
ImportNames   = Name, { ",", Name }, [ "," ] ;
Declaration   = [ "export" ], (TypeDeclaration | InterfaceDeclaration | FunctionDeclaration
              | ConstantDeclaration | ExternDeclaration)
              | Implementation | TestDeclaration | BenchDeclaration ;
ConstantDeclaration = "let", ( ConstantBinding | "(", NEWLINE, INDENT, ConstantBinding, { ConstantBinding }, DEDENT, ")", NEWLINE ) ;
ConstantBinding = Name, [ ":", Type ], "=", Expression, NEWLINE ;

TypeDeclaration = "type", Name, [ TypeParameters ], ":", NEWLINE,
                  INDENT, (RecordBody | AlternativeBody), DEDENT ;
RecordBody    = { Field } ;
Field         = Name, ":", Type, [ "=", Expression ], NEWLINE ;
AlternativeBody = CaseDeclaration, { CaseDeclaration } ;
CaseDeclaration = "case", Name, [ "(", Parameters, ")" ], NEWLINE ;
InterfaceDeclaration = "interface", Name, [ TypeParameters ], ":", NEWLINE,
                       INDENT, ContractBody, DEDENT ;
ContractBody  = OperationSignature, { OperationSignature } ;
OperationSignature = "def", Name, "(", [ FunctionParameters ], ")", "->", ResultType, NEWLINE ;
FunctionDeclaration = "def", Name, [ TypeParameters ], "(", [ FunctionParameters ], ")",
                      "->", ResultType, FunctionSuite ;
ResultType    = [ "ref" ], Type ;
(* `ref` marks a result that lends part of a borrowed parameter or the receiver; see ownership. A function type has no `ref`. *)
Implementation = "impl", NamedType, [ "for", NamedType ], ":", NEWLINE,
                 [ INDENT, MethodDeclaration, { MethodDeclaration }, DEDENT ] ;
(* With "for", the first NamedType is the interface and the second the type. Without it, the only NamedType is the type and the block declares its own methods. *)
MethodDeclaration = [ "var" ], "def", Name, "(", [ FunctionParameters ], ")", "->", ResultType, FunctionSuite ;
ExternDeclaration = "extern", "def", Name, "(", [ FunctionParameters ], ")", "->", ResultType, NEWLINE
                  | "extern", "type", Name, [ TypeParameters ], NEWLINE ;
FunctionSuite = ":", ("...", NEWLINE | Expression | SimpleStatement | NEWLINE, INDENT, { Statement }, DEDENT) ;
TestDeclaration = "test", PlainStringLiteral, Suite ;
(* A test body behaves as if it returns Result[Unit, Error]: completing, bare return, or `return ()` succeeds; try or return error(...) fails it. *)
(* Only canonical TestHooks implementations may omit operations; missing hooks are no-ops. *)
BenchDeclaration = "bench", PlainStringLiteral, [ "per", PositiveInteger ], Suite ;
(* `bench` is contextual: it starts a declaration only before a string literal. The body is one iteration (`per N` says it performs N operations, and `ms bench` then reports per operation), with a test body's result rules and no `fixture`; `ms bench` repeats and times it. *)
Parameters    = Parameter, { ",", Parameter }, [ "," ] ;
Parameter     = Name, ":", Type ;
FunctionParameters = FunctionParameter, { ",", FunctionParameter }, [ "," ] ;
FunctionParameter = Parameter, [ "=", Expression ] ;
CallbackParameters = CallbackParameter, { ",", CallbackParameter }, [ "," ] ;
CallbackParameter = Name, [ ":", Type ], [ "=", Expression ] ;
TypeParameters = "[", TypeParameter, { ",", TypeParameter }, [ "," ], "]" ;
TypeParameter = Name, [ ":", Bounds ], [ "=", Type ] ;
Bounds        = NamedType, { "&", NamedType } ;

Type          = NamedType | FunctionType | "(", Type, ")" ;
NamedType     = TypePath, [ TypeArguments ] ;
TypePath      = Name, { ".", Name } ;
TypeArguments = "[", Type, { ",", Type }, [ "," ], "]" ;
FunctionType  = "Callable", "[", "[", [ Type, { ",", Type } ], "]", ",", Type, "]" ;
```

- A `type` declares record fields or alternative cases, never both; its methods go in an `impl` block, `impl Type:` for its own or `impl Interface for Type:` for an interface. An `interface` holds only operation signatures. A nullary case is `case Ready`, without `()`. Names are unique per scope.
- A result type follows `->` after the parameter list (`def double(value: Int) -> Int:`). A lambda writes parameters without parentheses when none is typed (`lambda value: value * 2`), and with parentheses when it types a parameter or declares a result (`lambda (value: Int) -> Int: value * 2`).
- Named functions (`def`) need explicit parameter and result types; anonymous ones may infer them ([callback inference](../functions/function-values-and-closures.md#contextual-callback-inference)).
- Defaults: [function parameters](../functions/declarations-and-calls.md#default-arguments), [record fields](../types/records.md#construction), and `= none` on Optional interface parameters. Function types and alternative payloads have none. Parameter names in a `Callable` type do not exist: two function types are the same when their parameter types and result type match, and calls through function values are positional. No variadics or parameter patterns.
- A named function or method body may be `...` (`def commands() -> Commands: ...`), as may a type schema (`type Duration: ...`); the standard library uses this for runtime-bound implementations. Interface, implementation, test, bench, and control-flow suites are nonempty.
- Imports and declarations may interleave; order does not affect resolution. Import paths, test names, and bench names are plain literals (escapes allowed, no interpolation).
- `export` applies to types, interfaces, and named functions, not tests, benches, or `impl` blocks.
- `impl` blocks declare no type parameters, and `impl Type:` is accepted only in the module that declares `Type`: in `impl Contract[T] for Data[T]:`, `T` comes from the receiver type and bounds from the declarations. Every parameter in the signatures must occur in the receiver application, and operations and source methods cannot declare their own. Overlap follows [contracts](../types/contracts.md#generic-implementations).
- `&` only combines generic bounds, as in `T: Read & Closeable`; order is irrelevant. There is no intersection or refinement syntax for value types.
- No module-level statements or `var`; a top-level `let` is a [constant](../modules/declarations.md#constants). Snippets of local bindings are body fragments. Type paths add no wildcard imports; see [module rules](../modules/declarations.md).

## Statements and patterns

```ebnf
Suite         = ":", (SimpleStatement | NEWLINE, INDENT, Statement, { Statement }, DEDENT) ;
Statement     = SimpleStatement, NEWLINE
              | IfStatement | WhileStatement | ForStatement
              | WithStatement ;
SimpleStatement = Binding | Assignment | CompoundAssignment | ReturnStatement | "break" | "continue"
                | CallStatement ;
Binding       = ("let" | "var"), ( BindingEntry
              | "(", NEWLINE, { BindingEntry, NEWLINE }, ")" ) ;
BindingEntry  = (Name, [ ":", Type ] | PositionalPattern | RecordPattern), "=", Expression ;
Assignment    = (Name | Expression, ".", Name), "=", Expression ;
CompoundAssignment = Name, { ".", Name }, ( "+=" | "-=" | "*=" | "/=" | "%=" ), Expression ;
ReturnStatement = "return", [ Expression ] ;
CallStatement = Expression ;
IfStatement   = "if", [ "let", Name, "=" ], Expression, Suite,
                { "elif", [ "let", Name, "=" ], Expression, Suite },
                [ "else", Suite ] ;
WhileStatement = "while", Expression, Suite ;
ForStatement  = "for", Name, "in", Expression, Suite ;
WithStatement = "with", Expression, "as", Name, Suite ;
MatchExpression = "match", Expression, ":", NEWLINE, INDENT,
                 MatchArm, { MatchArm }, DEDENT ;
MatchArm      = "case", (CasePattern | LiteralPattern | "_"), ArmSuite ;
LiteralPattern = [ "-" ], Number | String | "True" | "False" ;
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

- `CallStatement` accepts a call or match and discards the result, or `try call()` when the success type is `Unit` ([propagation](../errors/propagation.md)). Bare names and arithmetic are not statements.
- Assignment replaces a `var` or record field. `target op= value` means `target = target op (value)`; write the operator and `=` adjacent. The target is a name or field path (`box.inner.count += 1`) with no call or index in the receiver. `+=` appends text; `-=` on text is an error.
- Only a simple name takes a type annotation. Positional patterns may be empty; empty record patterns are rejected. `_` is a wildcard and match payload placeholder only.
- Inline suites (functions, methods, tests, branches, loops, `with`) hold one simple statement, no nested compound statements. Functions and methods alone may hold one expression, which is returned:

```manuscript
def double(value: Int) -> Int: value * 2
def positive(value: Int) -> Bool:
    if value > 0: return True
    else: return False
```

- `elif` and `else` start on their own line at the `if` header's indentation; inline and indented branches may mix.
- A match arm holds one statement or value inline, or statements then a value when indented.
- Match patterns use positional payloads, not labels. On a contract view, a pattern names a complete concrete type and one receiver binding, with a final wildcard ([pattern matching](../control-flow/pattern-matching.md)).
- `match` is an expression even when discarded; loops and `with` are statements, and `if` is a statement. The conditional expression is `a if c else b` (a required `else`; chains nest in the final `else`).
- Local type, implementation, import, test, and bench declarations are rejected; a local function is a `def` statement, sugar for binding a `lambda` (it cannot call itself).
- `with` follows the [cleanup scopes](../cleanup/scopes.md) contract. There is no move, borrow, spawn, or deferred-call syntax.

## Rejected forms

```manuscript
let count = 3                       # Not a complete module item.
def wrong() -> Int:
  return 1                          # A suite requires four spaces.
def wrong() -> Int:
    let (first, second) = pair       # Parentheses are not a binding pattern.
```

Each example is an independent rejected form.

## Nesting limits

The parser rejects nesting deeper than 1000 levels (expressions, types, patterns, blocks, interpolated literals) and chains longer than 10000 operators, member accesses, calls, or indexes, reporting `parse: nesting exceeds 1000 levels`.

[Back to language basics](_index.md) · [Expressions and operators](expressions.md)
