---
title: "Reference"
linkTitle: "Reference"

description: >
  Complete technical reference for manuscript syntax, grammar, and built-in features.
---

Complete technical documentation for the manuscript programming language. This section provides detailed syntax definitions, grammar rules, and built-in functionality.

## Syntax Reference

### [Grammar](grammar/)
Complete formal grammar definition in ANTLR4 format.

### [Keywords](keywords/)
All reserved words and their usage in manuscript.

### [Operators](operators/)
Arithmetic, logical, comparison, and assignment operators.

### [Literals](literals/)
Number, string, boolean, and collection literals.

## Type System

### [Built-in Types](types/)
Primitive types, collection types, and type annotations.

### [Type Conversions](conversions/)
Implicit and explicit type conversion rules.

### [Type Inference](inference/)
How manuscript infers types from context.

## Language Constructs

### [Expressions](expressions/)
All expression types and evaluation rules.

### [Statements](statements/)
Control flow, declarations, and other statements.

### [Functions](functions/)
Function syntax, parameters, and calling conventions.

## Built-in Functions

### [Core Functions](builtins/)
Essential functions available in all manuscript programs.

### [String Functions](strings/)
String manipulation and processing functions.

### [Collection Functions](collections/)
Array, map, and set operations.

### [I/O Functions](io/)
Input, output, and file operations.

## Error Handling

### [Error Types](errors/)
Built-in error types and error creation.

### [Error Propagation](propagation/)
How errors flow through function calls.

### [Try Expressions](try/)
Using try for error handling.

## Module System

### [Import/Export](modules/)
Module declaration and dependency management.

### [Standard Library](stdlib/)
Built-in modules and their functions.

## Advanced Features

### [Pattern Matching](patterns/)
Match expressions and destructuring patterns.

### [Generics](generics/)
Generic types and functions (future feature).

### [Interfaces](interfaces/)
Interface definitions and implementations.

## Language Specification

### [Lexical Analysis](lexer/)
Token definitions and scanning rules.

### [Parse Tree](parser/)
Abstract syntax tree structure.

### [Semantic Analysis](semantics/)
Type checking and validation rules.

### [Code Generation](codegen/)
How manuscript compiles to Go.

## Examples

Each reference section includes practical examples showing the feature in use. For learning-oriented content, see the [Language Features](../constructs/) section.

## Notation

This reference uses the following notation:

- `keyword` - Literal keywords and symbols
- `identifier` - User-defined names
- `[optional]` - Optional syntax elements
- `{repeated}` - Elements that can be repeated
- `choice|alternative` - Syntax alternatives

## Quick Reference

### Variable Declaration
```ms
let name = value                    // inferred type
let name type = value               // explicit type  
let (name1 = value1, name2 = value2) // block declaration
```

### Function Declaration
```ms
fn name(param type) returnType {    // basic function
fn name(param type) returnType! {   // error-returning function
```

### Control Flow
```ms
if condition { ... }                // conditional
for item in collection { ... }      // iteration
match value { pattern: result }     // pattern matching
```

### Error Handling
```ms
try expression                      // propagate errors
check condition                     // exit if false
error("message")                    // create error
```

This reference provides the technical details needed for advanced manuscript usage and tooling development. 