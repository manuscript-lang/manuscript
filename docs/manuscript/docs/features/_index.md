---
title: "Language Features"
linkTitle: "Features"

description: >
  Complete guide to all manuscript language constructs and features.
---
# manuscript language features

This section covers all the core language constructs available in manuscript, organized by category.

## Core Language Constructs

### [Variables](variables/)
Variable declarations, type system, and type inference.

### [Functions](functions/)
Function definitions, parameters, return types, and closures.

### [Control Flow](control-flow/)
Conditional statements, loops, and pattern matching.

### [Data Structures](data-structures/)
Arrays, objects, maps, and custom types.

### [Piped Syntax](piped-syntax/)
Chain function calls using pipeline syntax for data processing workflows.

### [Error Handling](error-handling/)
Error types, handling patterns, and result types.

### [Modules](modules/)
Module system, imports, and exports.

### [Types and Interfaces](types-interfaces/)
Custom types, interfaces, and type system features.

## Language Design

manuscript is designed with these core principles:

- **Clarity** - Code should be easy to read and understand
- **Safety** - Type system helps prevent common errors  
- **Productivity** - Minimal boilerplate and intuitive syntax
- **Performance** - Efficient compilation to Go code

## Quick Reference

### Basic Syntax
```ms
// Variables
let name = "value"
let count int = 42

// Functions
fn functionName(param type) returnType {
  return value
}

// Control Flow
if condition {
  // code
} else {
  // code
}

for item in collection {
  // code
}

// Piped Syntax
data | transform | validate | save

// Types
type CustomType {
  field string
  count int
}
```

## Feature Status

The following features are currently implemented and documented:

- ✅ Variables and basic types
- ✅ Functions and parameters
- ✅ Control flow (if/else, loops)
- ✅ Basic data structures
- ✅ Piped syntax for function chaining
- ✅ Error handling with bang functions
- ✅ Pattern matching
- ✅ Module imports
- ✅ Custom types and interfaces 