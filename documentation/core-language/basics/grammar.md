+++
title = "Source grammar"
weight = 6
+++

# Source grammar

Use the grammar to resolve syntax questions during review; Manuscript is in alpha and syntax may change.

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::indented callback\nPASS example.ms::indented callback\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

fn apply(value: Int, transform: fn(Int) Int) Int:
    return transform(value)

test "indented callback":
    let result = apply(
        value: 3,
        transform: (
            fn(value: Int) Int:
                return value - 1
        ),
    )
    try expect_equal(result, 2)
```

```sh
ms test example.ms
```

```text
RUN example.ms::indented callback
PASS example.ms::indented callback
1 tests, 0 failed
```

- An enum contains bare variants; records contain fields. `opaque` can modify either declaration.
- Indent four spaces; plain `case` is an identifier, not a variant prefix.

## Numeric tokens

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

- `Expression` follows the [expression parser](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-syntax/src/parser.rs#L2145-L2392) and [operator binding powers](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-syntax/src/ast.rs#L568-L583).

## Modules, declarations, and types

```ebnf
Module        = { Import | Declaration } ;
Import        = "import", ( ImportNames | "(", ImportNames, [ "," ], ")" ), "from", PlainStringLiteral, NEWLINE ;
ImportNames   = Name, { ",", Name } ;
Declaration   = [ "export" ], (TypeDeclaration | EnumDeclaration | InterfaceDeclaration | FunctionDeclaration
              | ConstantDeclaration | ExternDeclaration)
              | Implementation | TestDeclaration | BenchDeclaration ;
ConstantDeclaration = "let", ( ConstantBinding | "(", NEWLINE, INDENT, ConstantBinding, { ConstantBinding }, DEDENT, ")", NEWLINE ) ;
ConstantBinding = Name, [ ":", Type ], "=", Expression, NEWLINE ;

TypeDeclaration = [ "opaque" ], "type", Name, [ TypeParameters ], ":",
                  ("...", NEWLINE | NEWLINE, INDENT, RecordBody, DEDENT) ;
RecordBody    = { Field } ;
Field         = Name, ":", Type, [ "=", Expression ], NEWLINE ;
EnumDeclaration = [ "opaque" ], "enum", Name, [ TypeParameters ], ":",
                  NEWLINE, INDENT, VariantDeclaration, { VariantDeclaration }, DEDENT ;
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
(* A test body behaves as if it returns Result[Unit, Error]: completing, bare return, or `return unit` succeeds; try or return error(...) fails it. *)
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

## Statements and patterns

```ebnf
Suite         = ":", (SimpleStatement | NEWLINE, INDENT, Statement, { Statement }, DEDENT) ;
Statement     = SimpleStatement, NEWLINE
              | IfStatement | WhileStatement | ForStatement ;
SimpleStatement = Binding | Assignment | CompoundAssignment | ReturnStatement | "break" | "continue"
                | CallStatement ;
Binding       = ("let" | "var"), ( BindingEntry
              | "(", NEWLINE, { BindingEntry, NEWLINE }, ")" ) ;
BindingEntry  = (Name, [ ":", Type ] | PositionalPattern | RecordPattern), "=", Expression ;
Assignment    = AssignmentTarget, "=", Expression ;
AssignmentTarget = Name, { ".", Name | "[", Expression, "]" } ;
CompoundAssignment = AssignmentTarget, ( "+=" | "-=" | "*=" | "/=" | "%=" ), Expression ;
ReturnStatement = "return", [ Expression ] ;
CallStatement = Expression ;
IfStatement   = "if", [ ("let" | "var"), Name, "=" ], Expression, Suite,
                { "else", "if", [ ("let" | "var"), Name, "=" ], Expression, Suite },
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

<span id="source-characters-and-tokens"></span><span id="layout-tokens"></span><span id="anonymous-function-suites-inside-delimiters"></span><span id="rejected-forms"></span><span id="nesting-limits"></span>

Next: [parser and lexical constraints](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-syntax/src/parser.rs); [Source files](syntax.md) · [Expressions and operators](expressions.md).
