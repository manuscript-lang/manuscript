+++
title = "Source grammar"
weight = 10.5
+++

# Source grammar

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

This page is the exact syntax reference. Use it to check how a declaration, expression, block, or pattern must be written. If you are learning the language, read [source structure](syntax.md) and the practical concept pages first.

Parsing checks the shape of source. The [expression rules](expressions.md), [type rules](../types/compatibility.md), and concept pages then determine whether that source is legal. The design does not prescribe a parser library or internal syntax-tree format.

## Source characters and tokens

Source is valid UTF-8 without a byte-order mark. LF and CRLF terminate physical lines; CRLF is normalized to LF before tokenization, and a lone CR is rejected. Identifiers use ASCII letters, digits, and underscores: `[A-Za-z_][A-Za-z0-9_]*`. Names are case-sensitive. A lone `_` is a pattern placeholder rather than an identifier. Unicode is supported in text literals and comments, not identifiers.

The reserved words are:

```text
and assert break case continue else export false fn for from if
impl import in interface let match not or return self test true try type
unit var while with
```

`self` names the implicit implementation receiver; it cannot be declared as a parameter or binding. Built-in type names and alternative constructors are names resolved by the type checker, not lexical keywords.

A `#` outside a text literal begins a comment through the physical line's end. Spaces separate tokens. Tabs in code, including indentation, are rejected; a tab in comment contents is permitted. Literal control characters inside text are rejected: use the defined [text escapes](text-and-bytes.md#string-literals). Semicolons and explicit backslash line continuation are rejected.

Numeric tokens use decimal digits only:

```ebnf
Digit         = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ;
NonzeroDigit  = "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ;
Whole         = "0" | NonzeroDigit, { Digit } ;
Fraction      = ".", Digit, { Digit } ;
Exponent      = ("e" | "E"), [ "+" | "-" ], Digit, { Digit } ;
IntLiteral    = Whole ;
FloatLiteral  = Whole, (Fraction, [ Exponent ] | Exponent) ;
DecimalLiteral = Whole, [ Fraction ], [ Exponent ], "d" ;
```

An adjacent identifier character cannot follow a numeric token, except for its defined `d` suffix. Leading zeros, digit separators, hexadecimal/binary notation, `.5`, and `1.` are rejected. An exponent without a fraction still selects Float: `1e3` is Float. A sign is an expression operator, not part of the token; the [numeric rules](numbers-and-booleans.md) define negative literal range checking. A dot starts a fraction only when followed by a digit. Consequently `2.seconds` consists of an Int literal, a dot, and a member name; the duration-unit contract determines its type.

## Layout tokens

At module level, code starts in column zero. A suite is a nonempty block introduced by `:` at the end of a logical header. Its first significant line is indented exactly four spaces beyond its header line's leading indentation. Further statements use that same indentation; nested suites add another four spaces. A dedent returns to an enclosing suite's indentation. Unexpected indentation and dedents to other columns are errors. Blank and comment-only lines do not open or close suites.

The grammar uses `NEWLINE`, `INDENT`, and `DEDENT` for these logical boundaries. End of file supplies the final `NEWLINE` if needed and closes outstanding suites. Empty bodies have no `pass` shorthand: each suite must contain a statement or declaration appropriate to its context.

Inside `()`, `[]`, and `{}`, ordinary physical newlines do not produce `NEWLINE`, `INDENT`, or `DEDENT`. Continuation lines must use spaces and a multiple of four for their leading indentation, but need not create a block. Delimiters must balance; a closing delimiter may align with the line that opened it. Trailing commas are allowed only in the comma-separated forms shown below.

### Anonymous-function suites inside delimiters

A function expression still has an indented statement suite when it appears inside a call, list, or grouping delimiter. This is the exception to newline suppression.

At a function expression's header-ending `:`:

1. Record the delimiter depth and the physical line's leading indentation, not the column of `fn`.
2. Require the next significant line to add exactly four spaces.
3. Apply normal statement newlines and block indentation at that recorded depth. Delimiters opened within body expressions still suppress continuation newlines.
4. End the suite when a significant line returns to the header indentation or less, closing body blocks first. Resume the surrounding delimiter's continuation rules.

A delimiter opened outside the function body cannot close at body indentation.

Group a function expression when a following comma needs to belong to an enclosing argument list:

```text
fn example() -> Int:
    return apply(
        value: 3,
        transform: (
            fn(value: Int) -> Int:
                return value - 1
        ),
    )
```

Here the function header has twelve leading spaces, its body sixteen, and the grouping close eight. The close ends the function suite before its comma separates the outer argument. The parentheses are grouping, not a tuple or another function kind. An ungrouped suite-bodied function can also be the final argument:

```text
fn example() -> Int:
    return apply(
        value: 3,
        transform: fn(value: Int) -> Int:
            return value - 1
    )
```

Its header has eight leading spaces, its body twelve, and the enclosing call closes at four. A single-line `fn(...) -> T: expression` body is rejected. Binding an anonymous function first and then passing its name is also valid. When a suite-bodied expression completes a surrounding simple statement with no enclosing expression delimiter still open, its suite boundary also terminates that statement: the parser supplies the outer `NEWLINE` after the expression's `DEDENT`. It does not require a second physical blank line. When a delimiter remains open, continuation resumes until that delimiter closes and the surrounding statement ends normally.

## Modules, declarations, and types

In the EBNF below, braces mean repetition and brackets mean an optional grammar part. Quoted brackets are actual source tokens. `Name` is an identifier, `StringLiteral` is defined by [text and bytes](text-and-bytes.md), and `Expression` is defined by [expressions](expressions.md).

```ebnf
Module        = { Import | Declaration } ;
Import        = "import", ( Name | "{", Name, { ",", Name }, [ "," ], "}" ),
                "from", PlainStringLiteral, NEWLINE ;
Declaration   = [ "export" ], (TypeDeclaration | InterfaceDeclaration | FunctionDeclaration)
              | Implementation | TestDeclaration ;

TypeDeclaration = "type", Name, [ TypeParameters ], ":", NEWLINE,
                  INDENT, (RecordBody | AlternativeBody), DEDENT ;
RecordBody    = Field, { Field } ;
Field         = Name, ":", Type, NEWLINE ;
AlternativeBody = CaseDeclaration, { CaseDeclaration } ;
CaseDeclaration = "case", Name, [ "(", Parameters, ")" ], NEWLINE ;
InterfaceDeclaration = "interface", Name, [ TypeParameters ], ":", NEWLINE,
                       INDENT, ContractBody, DEDENT ;
ContractBody  = OperationSignature, { OperationSignature } ;
OperationSignature = "fn", Name, "(", [ Parameters ], ")", "->", Type, NEWLINE ;

FunctionDeclaration = "fn", Name, [ TypeParameters ], "(", [ Parameters ], ")",
                      "->", Type, Suite ;
Implementation = "impl", NamedType, "for", NamedType, ":", NEWLINE,
                 INDENT, MethodDeclaration, { MethodDeclaration }, DEDENT ;
MethodDeclaration = "fn", Name, "(", [ Parameters ], ")", "->", Type, Suite ;
TestDeclaration = "test", PlainStringLiteral, Suite ;
Parameters    = Parameter, { ",", Parameter }, [ "," ] ;
Parameter     = Name, ":", Type ;
TypeParameters = "[", TypeParameter, { ",", TypeParameter }, [ "," ], "]" ;
TypeParameter = Name, [ ":", Bounds ] ;
Bounds        = NamedType, { "&", NamedType } ;

Type          = SharedContractType | NamedType | FunctionType | "(", Type, ")" ;
SharedContractType = NamedType, "&", "Shareable" ;
NamedType     = TypePath, [ TypeArguments ] ;
TypePath      = Name, { ".", Name } ;
TypeArguments = "[", Type, { ",", Type }, [ "," ], "]" ;
FunctionType  = "fn", "(", [ Parameters ], ")", "->", Type ;
```

A `type` declares either record fields or alternative cases. An `interface` declares one or more operation signatures. Mixing these forms is rejected. A nullary alternative uses `case Ready`, without `()`. Parameter names and declaration names must be unique within their applicable scope. Function parameters and results always have explicit types. Source parameter declarations do not accept default arguments, variadic parameters, parameter patterns, or anonymous-function type parameters. Trusted library/API contracts may define optional named arguments without exposing source default-parameter syntax; an omitted API argument is checked against that declared contract.

Imports and declarations may be interleaved; import visibility and declaration resolution do not depend on written order. Import paths and test names are plain text literals: escapes are permitted, interpolation is rejected. `export` applies to types, interfaces, and named module functions, not tests or implementation blocks. Implementation blocks declare no type parameters. In `impl Contract[T] for Data[T]:`, `T` comes from the receiver type declaration; applicable bounds come from the type and interface declarations.

Every parameter used in the interface or method signatures must occur in the nominal receiver application. Contract operations and implementation methods cannot declare their own type parameters. Implementation applicability and overlap follow [contracts](../types/contracts.md#generic-implementations).

`SharedContractType` requires its `NamedType` to resolve to an operation contract application. `Contract & Shareable` is a value type, including in fields, signatures, and generic arguments; it is not a general intersection facility. Reversed order, additional bounds, and refinements of noncontract types are rejected. Generic `Bounds` retain their existing conjunction syntax, where bound order does not affect the requirements. The compiler-defined name `Shareable` remains unavailable as a standalone value type.

There are no module-level executable statements or `let`/`var` bindings. Functions and tests contain executable code. A snippet showing local bindings without an enclosing function is a body fragment, not a complete `.ms` module. Type paths do not introduce wildcard/namespace imports or make a private type accessible; resolution follows [module rules](../../modules-and-capabilities/modules/declarations.md).

## Statements and patterns

```ebnf
Suite         = ":", NEWLINE, INDENT, Statement, { Statement }, DEDENT ;
Statement     = SimpleStatement, NEWLINE
              | IfStatement | WhileStatement | ForStatement | MatchStatement
              | WithStatement ;
SimpleStatement = Binding | Assignment | ReturnStatement | "break" | "continue"
                | "assert", Expression | CallStatement ;
Binding       = ("let" | "var"), (Name, [ ":", Type ] | PositionalPattern | RecordPattern),
                "=", Expression ;
Assignment    = Name, "=", Expression ;
ReturnStatement = "return", [ Expression ] ;
CallStatement = Expression ;
IfStatement   = "if", Expression, Suite,
                [ "else", (Suite | IfStatement) ] ;
WhileStatement = "while", Expression, Suite ;
ForStatement  = "for", Name, "in", Expression, Suite ;
WithStatement = "with", Name, "=", Expression, Suite ;
MatchStatement = "match", Expression, ":", NEWLINE, INDENT,
                 MatchArm, { MatchArm }, DEDENT ;
MatchArm      = CasePattern, Suite | "_", Suite ;
CasePattern   = CasePath, [ "(", PayloadNames, ")" ] ;
CasePath      = Name, [ TypeArguments ], { ".", Name } ;
PayloadNames  = (Name | "_"), { ",", (Name | "_") }, [ "," ] ;

BindingPattern = Name | PositionalPattern | RecordPattern ;
PositionalPattern = "[", [ BindingPattern, { ",", BindingPattern }, [ "," ] ], "]" ;
RecordPattern = "{", RecordEntry, { ",", RecordEntry }, [ "," ], "}" ;
RecordEntry   = Name, [ ":", BindingPattern ] ;
```

`CallStatement` must resolve to a call expression; arithmetic expressions or bare names are not standalone statements. Assignment replaces an existing `var` binding, not a field or list position. Only a simple name binding may carry a type annotation. Destructuring patterns infer their types from the checked initializer; annotate an intermediate name first when the initializer needs context. Positional patterns can be empty, selecting an empty fixed result or list. Empty record patterns are rejected because they bind nothing. `_` is allowed in match payloads and as a match wildcard, not as an ordinary binding or destructuring elision.

`else if` is two words; `elif` is not syntax. Match patterns use exact positional case payloads, not constructor argument labels. Their exhaustiveness, wildcard position, and binding checks are in [pattern matching](../control-flow/pattern-matching.md). `if`, `match`, loops, and `with` are statements, not value-producing expressions. Local type/implementation/import/test declarations are not accepted. Nested named function declarations are rejected; bind an anonymous function to a local name instead.

The existing [with construct](../../ownership-and-cleanup/cleanup/scopes.md) supplies its cleanup contract. This grammar does not define a move, borrow, consuming function kind, spawn keyword, or deferred-call construct. Runtime APIs are checked according to their own declarations and may impose more constraints on otherwise ordinary calls and list literals.

## Rejected forms

```text
let count = 3                       # Not a complete module item.
fn wrong(value: Int = 3) -> Int:     # Default parameter syntax is rejected.
    return value
fn wrong() -> Int:
  return 1                          # A suite requires four spaces.
fn wrong() -> Int:
    let (first, second) = pair       # Parentheses are not a binding pattern.
    return if true: 1 else: 2        # if is not an expression.
```

Each example is an independent rejected form. A syntax error does not require the parser to continue and produce further type diagnostics for that fragment.

[Back to language basics](_index.md) · [Expressions and operators](expressions.md)
