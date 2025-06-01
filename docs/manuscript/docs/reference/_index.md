---
title: "Reference: The Manuscript Lexicon & Grammar Codex"
linkTitle: "Reference"

description: >
  The complete, no-nonsense (well, mostly) technical reference for Manuscript syntax, grammar, built-in features, and all the nitty-gritty details.
---

Welcome, seeker of precision, to the Manuscript Reference Codex! This is where we lay out the aitches and tees of the language – the complete technical documentation. If you need the absolute, undeniable truth about syntax definitions, grammar rules, or built-in functionality, you've come to the right sanctum. Consider this your detailed map to the Manuscript linguistic landscape.

> Words have their own rules,
> Syntax, precise and so clear,
> Code's firm foundation.

## Syntax Reference: The Laws of the Language

Herein lie the fundamental rules of Manuscript grammar and structure.

### [Grammar](grammar/)
The complete, unabridged, formal grammar definition in ANTLR4 format. For those who *really* want to know.

### [Keywords](keywords/)
A comprehensive list of all reserved words in Manuscript and how they're employed (or rather, how *you* must employ them).

### [Operators](operators/)
The symbols of power: arithmetic, logical, comparison, and assignment operators, all laid bare.

### [Literals](literals/)
How to write down the actual values: numbers, strings, booleans, and the surprisingly literal ways to define collections.

## Type System: The DNA of Your Data

Understanding Manuscript's type system is key to wielding its power effectively.

### [Built-in Types](types/)
The fundamental building blocks: primitive types, collection types, and the art of type annotations.

### [Type Conversions](conversions/)
The alchemical rules for transforming one type into another, both implicitly and explicitly.

### [Type Inference](inference/)
Peer into Manuscript's mind and see how it cleverly infers types from their context (most of the time).

## Language Constructs: Building Blocks of Code

The essential structures you'll use to build your Manuscript masterpieces.

### [Expressions](expressions/)
Delve into all expression types and the sacred rules of their evaluation.

### [Statements](statements/)
From control flow directives to declarations and beyond – the commands that make things happen.

### [Functions](functions/)
The syntax of spellcraft: function definitions, parameter passing, and calling conventions.

## Built-in Functions: Spells Provided by the System

Manuscript comes with a handy toolkit of pre-made functions.

### [Core Functions](builtins/)
The absolute essentials, available in every Manuscript program, no import incantations required.

### [String Functions](strings/)
For when you need to slice, dice, search, or otherwise transmogrify strings.

### [Collection Functions](collections/)
Powerful operations for arrays, maps, and sets. Let the data juggling commence!

### [I/O Functions](io/)
The conduits to the outside world: input, output, and file operations.

## Error Handling: Navigating Life's Little Mishaps

How Manuscript deals with the inevitable boo-boos.

### [Error Types](errors/)
A bestiary of built-in error types and the methods for forging your own.

### [Error Propagation](propagation/)
Follow the journey of an error as it bubbles up through your function calls. It's like a game of hot potato, but with more stack traces.

### [Try Expressions](try/)
The primary mechanism for bravely attempting operations that might just go sideways, and how to handle the aftermath.

## Module System: Keeping Your Workshop Tidy

Organizing your code for clarity and reusability.

### [Import/Export](modules/)
The spells for declaring modules and managing dependencies between them. Share your magic, or borrow from others!

### [Standard Library](stdlib/)
A tour of the built-in modules and their functions, packaged with Manuscript for your convenience.

## Advanced Features: For the Seasoned Sorcerer

Venturing into more complex enchantments.

### [Pattern Matching](patterns/)
The art of `match` expressions and destructuring patterns for elegant data inspection and conditional logic.

### [Generics](generics/)
Crafting flexible types and functions that can work with a variety of specific types. (Note: This might be a future feature, check its current status!)

### [Interfaces](interfaces/)
Defining contracts and capabilities with interface definitions and their implementations.

## Language Specification: The Deepest Lore

For language implementers, tool builders, or the exceptionally curious.

### [Lexical Analysis](lexer/)
The very atoms of the language: token definitions and the rules for scanning them.

### [Parse Tree](parser/)
Understanding the abstract syntax tree (AST) structure that represents your code internally.

### [Semantic Analysis](semantics/)
The rules for type checking, validation, and ensuring your code makes logical sense (at least to the compiler).

### [Code Generation](codegen/)
A peek under the hood at how Manuscript code is transmuted into efficient Go code.

## A Note on Examples

While this is a reference guide focused on the "what" and "how" of syntax and features, each section strives to include practical examples. For more learning-oriented explanations and broader examples, please consult the [Language Features](../constructs/) section and the [Examples](../examples/) section.

## Notation Used Herein

To maintain a semblance of order and clarity in this codex, we use the following notation:

- `keyword` - Literal keywords and symbols you'd type, like `fn` or `+`.
- `identifier` - Placeholder for names you, the programmer, would define (e.g., variable names, function names).
- `[optional_element]` - Indicates syntax elements that you can choose to include or omit.
- `{repeated_element}` - Denotes elements that can appear one or more times.
- `choice_A | choice_B` - Signifies that you must choose one of the alternatives.

## Quick Reference: Your Pocket Spell Sheet

A very brief reminder of some common incantations. For full details, consult the specific sections linked above!

### Variable Declaration
```ms
let name = value                    // Type is cleverly inferred by Manuscript
let name type = value               // You explicitly state the type
let (name1 = value1, name2 = value2) // A block for declaring multiple variables
```

### Function Declaration
```ms
fn name(param type) returnType { /* spell body */ }   // A basic function
fn name(param type) returnType! { /* spell body */ }  // A function that might signal an error!
```

### Control Flow
```ms
if condition { /* then this */ } else { /* or that */ } // Making decisions
for item in collection { /* do for each */ }           // Looping through things
match value { pattern: result }                        // Elegant pattern matching
```

### Error Handling
```ms
try expression                     // Bravely attempt, propagate error if it occurs
check condition                    // Ensure true, or function exits with error
error("a descriptive message")     // Create and signal a new error
```

This reference is your faithful companion for delving into the precise mechanics of Manuscript. May it serve you well in your advanced studies and tool-building endeavors!
