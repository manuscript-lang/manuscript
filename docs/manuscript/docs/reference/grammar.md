---
title: "Grammar"
linkTitle: "Grammar"
weight: 10
description: >
  Complete formal grammar definition for manuscript in ANTLR4 format.
---

The manuscript language grammar is defined using ANTLR4. This page provides the complete formal grammar definition.

## Grammar Files

The manuscript grammar is split into two main files:

- **ManuscriptLexer.g4** - Lexical rules (tokens)
- **Manuscript.g4** - Parser rules (syntax)

## Core Grammar Rules

### Program Structure
```antlr
program: statements EOF ;

statements: statement+ ;

statement
    : functionDeclaration
    | variableDeclaration  
    | typeDeclaration
    | importDeclaration
    | exportDeclaration
    | expressionStatement
    ;
```

### Function Declarations
```antlr
functionDeclaration
    : 'fn' IDENTIFIER '(' parameterList? ')' returnType? bangOperator? block
    ;

parameterList: parameter (',' parameter)* ;

parameter: IDENTIFIER type ;

returnType: type ;

bangOperator: '!' ;
```

### Variable Declarations
```antlr
variableDeclaration
    : 'let' IDENTIFIER type? '=' expression
    | 'let' '(' variableList ')'
    ;

variableList: variableAssignment (',' variableAssignment)* ;

variableAssignment: IDENTIFIER type? '=' expression ;
```

### Type System
```antlr
type
    : IDENTIFIER                    // Basic type
    | type '[' ']'                  // Array type
    | type '!'                      // Error type
    | '(' type (',' type)* ')'      // Tuple type
    ;
```

### Expressions
```antlr
expression
    : primary
    | expression '.' IDENTIFIER
    | expression '[' expression ']'
    | expression '(' argumentList? ')'
    | 'try' expression
    | 'match' expression '{' matchCases '}'
    | binaryExpression
    ;

primary
    : IDENTIFIER
    | literal
    | '(' expression ')'
    | arrayLiteral
    | objectLiteral
    | mapLiteral
    | setLiteral
    ;
```

### Literals
```antlr
literal
    : NUMBER
    | STRING
    | BOOLEAN
    | 'null'
    | 'void'
    ;

arrayLiteral: '[' expressionList? ']' ;

objectLiteral: '{' objectFields? '}' ;

mapLiteral: '[' mapFields? ']' ;

setLiteral: '<' expressionList? '>' ;
```

## Complete Grammar

For the complete, up-to-date grammar definition, see the source files:

- [ManuscriptLexer.g4](https://github.com/manuscript-lang/manuscript/blob/main/internal/grammar/ManuscriptLexer.g4)
- [Manuscript.g4](https://github.com/manuscript-lang/manuscript/blob/main/internal/grammar/Manuscript.g4)

## Grammar Evolution

The grammar is actively developed. Changes are documented in:

- [Grammar changelog](https://github.com/manuscript-lang/manuscript/blob/main/docs/grammar-changelog.md)
- [Language design decisions](https://github.com/manuscript-lang/manuscript/blob/main/docs/language-design.md) 