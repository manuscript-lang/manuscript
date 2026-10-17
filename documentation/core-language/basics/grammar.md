+++
title = "Source grammar"
weight = 6
+++

# Source grammar

This page is the exact syntax reference. Use it to check how a declaration, expression, block, or pattern must be written. If you are learning the language, read [source structure](syntax.md) and the practical concept pages first.

Parsing checks the shape of source. The [expression rules](expressions.md), [type rules](../types/compatibility.md), and concept pages then determine whether that source is legal.

## Source characters and tokens

Source is valid UTF-8 without a byte-order mark. LF and CRLF terminate physical lines; CRLF is normalized to LF before tokenization, and a lone CR is rejected everywhere, including inside comments. Identifiers use ASCII letters, digits, and underscores: `[A-Za-z_][A-Za-z0-9_]*`. Names are case-sensitive. A lone `_` is a pattern placeholder rather than an identifier. Unicode is supported in text literals and comments, not identifiers.

The reserved words are:

```manuscript
and break case continue else export false fixture fn for if
impl import in interface let match not or return self test true try type
unit var while with
```

`from` is a keyword only after the names of an import; elsewhere it is an ordinary name, as in `let from = 2`.

`fixture` names the file fixture inside test blocks when a local `make_fixture`
factory returns a concrete `TestHooks` implementer. It cannot be declared as a
parameter or binding. See file fixtures.

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

At module level, code starts in column zero. A suite is introduced by `:`. An inline suite contains exactly one simple statement after the colon; an indented suite is a nonempty block with the colon at the end of a logical header. An indented suite's first significant line is indented exactly four spaces beyond its header line's leading indentation. Further statements use that same indentation; nested suites add another four spaces. A dedent returns to an enclosing suite's indentation. Unexpected indentation and dedents to other columns are errors. Blank and comment-only lines do not open or close suites.

The grammar uses `NEWLINE`, `INDENT`, and `DEDENT` for these logical boundaries. End of file supplies the final `NEWLINE` if needed and closes outstanding suites. Empty bodies have no `pass` shorthand: each suite must contain a statement or declaration appropriate to its context.

Inside `()`, `[]`, and `{}`, ordinary physical newlines do not produce `NEWLINE`, `INDENT`, or `DEDENT`. Continuation lines must use spaces and a multiple of four for their leading indentation, but need not create a block. A line whose first token is `|`, or `.` not followed by a digit or another `.`, continues the previous statement outside delimiters as well, with no `NEWLINE`, `INDENT`, or `DEDENT`. Blank and comment-only lines before it are skipped, and it must be indented exactly four spaces past the line where the statement began. See [pipe flows](expressions.md#pipe-flows). Delimiters must balance; a closing delimiter may align with the line that opened it. Trailing commas are allowed only in the comma-separated forms shown below.

### Anonymous-function suites inside delimiters

A function expression may have an inline suite or an indented statement suite inside a call, list, or grouping delimiter. An inline body ends at the enclosing comma or closing delimiter. An indented body follows these layout rules. This is the exception to newline suppression.

At a function expression's header-ending `:`:

1. Record the delimiter depth and the physical line's leading indentation, not the column of `fn`.
2. Require the next significant line to add exactly four spaces.
3. Apply normal statement newlines and block indentation at that recorded depth. Delimiters opened within body expressions still suppress continuation newlines.
4. End the suite when a significant line returns to the header indentation or less, closing body blocks first. Resume the surrounding delimiter's continuation rules.

A delimiter opened outside the function body cannot close at body indentation.

Group a function expression when a following comma needs to belong to an enclosing argument list:

```manuscript
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

```manuscript
fn example() -> Int:
    return apply(
        value: 3,
        transform: fn(value: Int) -> Int:
            return value - 1
    )
```

Its header has eight leading spaces, its body twelve, and the enclosing call closes at four. Use `fn(value): value - 1` when context supplies the parameter type. An inline function expression body returns its value; indented bodies retain explicit returns. Binding an anonymous function first and then passing its name is also valid. When a suite-bodied expression completes a surrounding simple statement with no enclosing expression delimiter still open, its suite boundary also terminates that statement: the parser supplies the outer `NEWLINE` after the expression's `DEDENT`. It does not require a second physical blank line. When a delimiter remains open, continuation resumes until that delimiter closes and the surrounding statement ends normally.

To continue with another argument after an ungrouped indented function, put the separating comma on its own line at the function header's indentation:

```manuscript
fn example() -> Int:
    return apply(
        transform: fn(value: Int) -> Int:
            return value - 1
        ,
        value: 3,
    )
```

The dedented comma ends the function suite and separates the arguments. A comma after `return value - 1` remains inside the function body and is rejected. Grouping the function, as above, also allows another argument after `),`.

## Modules, declarations, and types

In the EBNF below, braces mean repetition and brackets mean an optional grammar part. Quoted brackets are actual source tokens. `Name` is an identifier, `StringLiteral` is defined by [text and bytes](text-and-bytes.md), and `Expression` is defined by [expressions](expressions.md).

```ebnf
Module        = { Import | Declaration } ;
Import        = "import", ( Name | "{", Name, { ",", Name }, [ "," ], "}" ),
                "from", PlainStringLiteral, NEWLINE ;
Declaration   = [ "export" ], (TypeDeclaration | InterfaceDeclaration | FunctionDeclaration
              | ConstantDeclaration)
              | Implementation | TestDeclaration ;
ConstantDeclaration = "let", Name, [ ":", Type ], "=", Expression, NEWLINE ;

TypeDeclaration = "type", Name, [ TypeParameters ], ":", NEWLINE,
                  INDENT, (RecordBody | AlternativeBody), DEDENT ;
RecordBody    = { Field | ReceiverDeclaration } ;
Field         = Name, ":", Type, [ "=", Expression ], NEWLINE ;
AlternativeBody = CaseDeclaration, { CaseDeclaration | ReceiverDeclaration } ;
CaseDeclaration = "case", Name, [ "(", Parameters, ")" ], NEWLINE ;
InterfaceDeclaration = "interface", Name, [ TypeParameters ], ":", NEWLINE,
                       INDENT, ContractBody, DEDENT ;
ContractBody  = OperationSignature, { OperationSignature } ;
OperationSignature = "fn", Name, "(", [ FunctionParameters ], ")", "->", Type, NEWLINE ;
ReceiverDeclaration = "fn", Name, [ TypeParameters ], "(", [ FunctionParameters ], ")",
                      "->", Type, FunctionSuite ;

FunctionDeclaration = "fn", Name, [ TypeParameters ], "(", [ FunctionParameters ], ")",
                      "->", Type, FunctionSuite ;
Implementation = "impl", NamedType, "for", NamedType, ":", NEWLINE,
                 [ INDENT, MethodDeclaration, { MethodDeclaration }, DEDENT ] ;
MethodDeclaration = "fn", Name, "(", [ FunctionParameters ], ")", "->", Type, FunctionSuite ;
FunctionSuite = ":", (Expression | SimpleStatement | NEWLINE, INDENT, { Statement }, DEDENT) ;
TestDeclaration = "test", PlainStringLiteral, Suite ;
(* A test body behaves as if it returns Result[Unit, Error]: completing, bare return, or return unit succeeds; try or return error(...) fails it. *)
(* Only canonical TestHooks implementations may omit operations; missing hooks are no-ops. *)
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
FunctionType  = "fn", "(", [ Parameters ], ")", "->", Type ;
```

A `type` declares record fields or alternative cases; these data forms cannot be mixed. It may also contain receiver function declarations with ordinary function headers and suites, as used by the standard library. An `interface` contains only operation signatures. A nullary alternative uses `case Ready`, without `()`. Parameter names and declaration names must be unique within their applicable scope. Named function parameters and results have explicit types. Anonymous parameter types may come from a known function context, and anonymous result types may come from context or the checked body; see [callback inference](../functions/function-values-and-closures.md#contextual-callback-inference). Function declarations and expressions with bodies accept [default arguments](../functions/declarations-and-calls.md#default-arguments). Record fields accept [default expressions](../types/records.md#construction). Interface signatures may declare `= none` defaults on Optional parameters. Function types and alternative payloads have no defaults. Variadic parameters, parameter patterns, and anonymous-function type parameters are not accepted. An omitted argument is checked against its declared contract.

Named function and method suites may be empty: `fn commands() -> Commands:` followed by a newline is valid syntax. The standard library uses these empty functions for implementations supplied by its pinned runtime bindings. Empty type schemas likewise use `type Duration:` with a newline. No parser mode or `native` keyword changes the syntax. Application functions still need valid return behavior, and source receiver implementations use explicit `impl` blocks. Interface, implementation, test, and control-flow suites remain nonempty.

Imports and declarations may be interleaved; import visibility and declaration resolution do not depend on written order. Import paths and test names are plain text literals: escapes are permitted, interpolation is rejected. `export` applies to types, interfaces, and named module functions, not tests or implementation blocks. Implementation blocks declare no type parameters. In `impl Contract[T] for Data[T]:`, `T` comes from the receiver type declaration; applicable bounds come from the type and interface declarations.

Every parameter used in the interface or method signatures must occur in the nominal receiver application. Contract operations and implementation methods cannot declare their own type parameters. Implementation applicability and overlap follow [contracts](../types/contracts.md#generic-implementations).

Value types have no intersection/refinement syntax. `&` is used only to combine generic bounds, such as `T: Read & Closeable`; bound order does not affect the requirements. `Synchronized[T]` and `SynchronizedGuard[T]` are ordinary imported types, and lock scopes use existing `with` syntax.

There are no module-level executable statements or `var` bindings. A module-level `let` declares a [constant](../modules/declarations.md#constants); functions and tests contain all other executable code. A snippet showing local bindings without an enclosing function is a body fragment, not a complete `.ms` module. Type paths do not introduce wildcard/namespace imports or make a private type accessible; resolution follows [module rules](../modules/declarations.md).

## Statements and patterns

```ebnf
Suite         = ":", (SimpleStatement | NEWLINE, INDENT, Statement, { Statement }, DEDENT) ;
Statement     = SimpleStatement, NEWLINE
              | IfStatement | WhileStatement | ForStatement
              | WithStatement ;
SimpleStatement = Binding | Assignment | CompoundAssignment | ReturnStatement | "break" | "continue"
                | CallStatement ;
Binding       = ("let" | "var"), (Name, [ ":", Type ] | PositionalPattern | RecordPattern),
                "=", Expression ;
Assignment    = (Name | Expression, ".", Name), "=", Expression ;
CompoundAssignment = Name, { ".", Name }, ( "+=" | "-=" | "*=" | "/=" | "%=" ), Expression ;
ReturnStatement = "return", [ Expression ] ;
CallStatement = Expression ;
IfStatement   = "if", [ "let", Name, "=" ], Expression, Suite,
                [ "else", (Suite | IfStatement) ] ;
WhileStatement = "while", Expression, Suite ;
ForStatement  = "for", Name, "in", Expression, Suite ;
WithStatement = "with", Name, "=", Expression, Suite ;
MatchExpression = "match", Expression, ":", NEWLINE, INDENT,
                 MatchArm, { MatchArm }, DEDENT ;
MatchArm      = (CasePattern | "_"), ArmSuite ;
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

`CallStatement` accepts a call or match expression and discards its result. It also accepts `try call()` when the Result success type is `Unit` (see [propagation](../errors/propagation.md)); arithmetic expressions or bare names are not standalone statements. A match arm may end with any expression to produce its value. Assignment replaces an existing `var` binding or updates a record field. A compound assignment `target op= value` means `target = target op (value)` with the right side grouped as one operand, so `total -= a - b` subtracts the whole difference. The operator and `=` must be adjacent (`+ =` is two tokens and is rejected). The target is a name or a field reached through names (`box.inner.count += 1`); a receiver containing a call or index is rejected so that it runs once. Operand and result types follow the binary operator, so `+=` also appends text and `-=` on text is a type error. Collection positions are updated through methods. Only a simple name binding may carry a type annotation. Destructuring patterns infer their types from the checked initializer; annotate an intermediate name first when the initializer needs context. Positional patterns can be empty, selecting an empty fixed result or list. Empty record patterns are rejected because they bind nothing. `_` is allowed in match payloads and as a match wildcard, not as an ordinary binding or destructuring elision.

Inline suites work for functions, methods, tests, branches, loops, and cleanup scopes. They contain one simple statement, with no semicolon separators or nested compound statements. A function or method may instead contain one expression, which is implicitly returned. This expression shorthand applies only to callable bodies, not to tests or control-flow suites. For example:

```manuscript
fn double(value: Int) -> Int: value * 2
fn positive(value: Int) -> Bool:
    if value > 0: return true
    else: return false
```

`else` and `else if` must start on separate lines at the corresponding `if` header's indentation. Each branch may have its own inline body. Inline and indented branches may be mixed.

A short match arm contains one statement or value expression after its colon; an indented arm may contain statements followed by a value.

`else if` is two words; `elif` is not syntax. Alternative match patterns use exact positional case payloads, not constructor argument labels. On a contract view, the same pattern syntax names a complete concrete record or alternative type and exactly one receiver binding; a final wildcard is required. Their exhaustiveness, wildcard position, and binding checks are in [pattern matching](../control-flow/pattern-matching.md). `match` is an expression, including when its value is discarded on a line of its own. `if`, loops, and `with` are statements. Local type/implementation/import/test declarations are not accepted. Nested named function declarations are rejected; bind an anonymous function to a local name instead.

The existing [with construct](../cleanup/scopes.md) supplies its cleanup contract. This grammar does not define a move, borrow, consuming function kind, spawn keyword, or deferred-call construct. Runtime APIs are checked according to their own declarations and may impose more constraints on otherwise ordinary calls and list literals.

## Rejected forms

```manuscript
let count = 3                       # Not a complete module item.
fn wrong() -> Int:
  return 1                          # A suite requires four spaces.
fn wrong() -> Int:
    let (first, second) = pair       # Parentheses are not a binding pattern.
    return if true: 1 else: 2        # if is not an expression.
```

Each example is an independent rejected form. A syntax error does not require the parser to continue and produce further type diagnostics for that fragment.

## Nesting limits

The parser rejects expressions, types, patterns, blocks, and text literals nested inside interpolations nested more than 1000 levels deep, and a single chain of more than 10000 operators, member accesses, calls, or indexes. The diagnostic names the position (`parse: nesting exceeds 1000 levels`) so generated or pasted input cannot exhaust the compiler's stack.

[Back to language basics](_index.md) · [Expressions and operators](expressions.md)
