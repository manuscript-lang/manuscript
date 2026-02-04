// Shared Error Utilities for LLM-friendly error messages
// All errors should provide: what's wrong, where, and hints for fixing

export interface SourceLocation {
  line: number;
  column: number;
  offset?: number;
}

export interface ErrorInfo {
  message: string;
  hint?: string;
  loc: SourceLocation;
}

// Format error message with location - used by all error classes
export function formatErrorMessage(message: string, loc: SourceLocation, hint?: string): string {
  let msg = `${message} at line ${loc.line}, column ${loc.column}`;
  if (hint) {
    msg += `. Hint: ${hint}`;
  }
  return msg;
}

// Common error messages with hints for lexer errors
export const LexerErrors = {
  unterminatedString: (quote: string = '"') => ({
    message: "Unterminated string literal",
    hint: `Add a closing ${quote} to complete the string`,
  }),
  unterminatedMultilineString: () => ({
    message: "Unterminated multiline string",
    hint: 'Add closing """ to complete the multiline string',
  }),
  unterminatedRawString: () => ({
    message: "Unterminated raw string",
    hint: 'Raw strings start with r" and must end with "',
  }),
  unterminatedRawMultilineString: () => ({
    message: "Unterminated raw multiline string",
    hint: 'Add closing """ to complete the raw multiline string',
  }),
  unterminatedByteString: () => ({
    message: "Unterminated byte string",
    hint: 'Byte strings start with b" and must end with "',
  }),
  invalidEscapeSequence: (char: string) => ({
    message: `Invalid escape sequence: \\${char}`,
    hint: `Valid escapes: \\n \\t \\r \\\\ \\" \\' \\0 \\x## \\u{...}. Use r"..." for raw strings`,
  }),
  unexpectedCharacter: (char: string) => ({
    message: `Unexpected character: '${char}'`,
    hint: "Check for typos or unsupported characters",
  }),
  inconsistentIndentation: (expected: number, got: number) => ({
    message: `Inconsistent indentation: expected ${expected} spaces, got ${got}`,
    hint: "Use consistent spacing for indentation (2 or 4 spaces recommended)",
  }),
};

// Common error messages with hints for parser errors
export const ParserErrors = {
  unexpectedToken: (got: string, context?: string) => ({
    message: context 
      ? `Unexpected token '${got}' ${context}`
      : `Unexpected token: '${got}'`,
    hint: "Check syntax or remove unexpected token",
  }),
  expectedToken: (expected: string, got: string) => ({
    message: `Expected '${expected}', got '${got}'`,
    hint: `Add '${expected}' at this position`,
  }),
  expectedExpression: (got: string) => ({
    message: `Expected expression, got '${got}'`,
    hint: "Provide a value, variable, or expression here",
  }),
  expectedPattern: (got: string) => ({
    message: `Expected pattern, got '${got}'`,
    hint: "Use an identifier, literal, or destructuring pattern",
  }),
  expectedType: (got: string) => ({
    message: `Expected type annotation, got '${got}'`,
    hint: "Provide a type like: number, string, bool, [T], or custom type",
  }),
  expectedName: (got: string) => ({
    message: `Expected identifier name, got '${got}'`,
    hint: "Use a valid identifier (letters, numbers, underscores, starting with letter)",
  }),
  expectedNewline: (got: string) => ({
    message: `Expected newline, got '${got}'`,
    hint: "Add a line break here or check for missing statement separator",
  }),
  emptyParentheses: () => ({
    message: "Empty parentheses",
    hint: "Use () => expr for empty-parameter lambda, or remove if not needed",
  }),
  lambdaParamMustBeIdentifier: () => ({
    message: "Lambda parameter must be an identifier",
    hint: "Use simple names for lambda params: (x, y) => x + y",
  }),
  expectedTypeOrFn: (got: string) => ({
    message: `Expected 'type' or 'fn' declaration, got '${got}'`,
    hint: "Use 'type Name' for types or 'fn name()' for functions",
  }),
  unexpectedTokenInContext: (got: string) => ({
    message: `Unexpected token in context expression: '${got}'`,
    hint: "Context expressions expect capability bindings",
  }),
  multipleInheritanceNotAllowed: () => ({
    message: "Multiple inheritance is not allowed",
    hint: "A type can only extend one parent type. Use composition for multiple behaviors",
  }),
};

// Common error messages with hints for type checker errors
export const TypeErrors = {
  typeAlreadyDefined: (name: string) => ({
    message: `Type '${name}' is already defined`,
    hint: "Choose a different name or remove the duplicate definition",
  }),
  functionAlreadyDefined: (name: string) => ({
    message: `Function '${name}' is already defined`,
    hint: "Choose a different name or remove the duplicate definition",
  }),
  variableAlreadyDefined: (name: string) => ({
    message: `Variable '${name}' is already defined`,
    hint: "Choose a different name or use assignment (=) to update existing variable",
  }),
  unknownIdentifier: (name: string) => ({
    message: `Unknown identifier '${name}'`,
    hint: "Check spelling, or declare the variable before using it",
  }),
  breakOutsideLoop: () => ({
    message: "'break' statement outside of loop",
    hint: "'break' can only be used inside 'for' or 'while' loops",
  }),
  continueOutsideLoop: () => ({
    message: "'continue' statement outside of loop",
    hint: "'continue' can only be used inside 'for' or 'while' loops",
  }),
  returnOutsideFunction: () => ({
    message: "'return' statement outside of function",
    hint: "'return' can only be used inside function bodies",
  }),
  returnMissingValue: (returnType: string) => ({
    message: `Return statement must have a value of type '${returnType}'`,
    hint: `Add a return value: return someValue`,
  }),
  yieldOutsideGenerator: () => ({
    message: "'yield' outside of generator function",
    hint: "Mark the function as 'gen fn' to use yield",
  }),
  cannotAssignToImmutable: (name: string) => ({
    message: `Cannot assign to immutable variable '${name}'`,
    hint: "Use 'let' instead of 'const' to allow reassignment",
  }),
  typeMismatch: (expected: string, got: string) => ({
    message: `Type '${got}' is not assignable to type '${expected}'`,
    hint: `Expected '${expected}' but got '${got}'. Check the value or type annotation`,
  }),
  operatorRequiresType: (op: string, required: string, got: string) => ({
    message: `Operator '${op}' requires ${required}, got '${got}'`,
    hint: `Convert the value to ${required} or use a different operator`,
  }),
  cannotCompare: (left: string, right: string) => ({
    message: `Cannot compare '${left}' and '${right}'`,
    hint: "Comparison operators work on values of compatible types",
  }),
  wrongArgumentCount: (expected: string, got: number) => ({
    message: `Expected ${expected} argument(s), got ${got}`,
    hint: "Check the function signature and provide the correct number of arguments",
  }),
  unknownParameter: (name: string, available: string[]) => ({
    message: `Unknown parameter '${name}'`,
    hint: available.length > 0 
      ? `Available parameters: ${available.join(", ")}`
      : "Check the function signature for valid parameter names",
  }),
  propertyNotExist: (prop: string, type: string) => ({
    message: `Property '${prop}' does not exist on type '${type}'`,
    hint: "Check property name spelling or verify the type has this property",
  }),
  indexTypeMismatch: (expected: string, got: string) => ({
    message: `Index type '${got}' is not assignable to '${expected}'`,
    hint: `Use a ${expected} value to index this collection`,
  }),
  methodOverrideParamMismatch: (method: string, type: string, base: string) => ({
    message: `Method '${method}' in '${type}' has different parameters than in base type '${base}'`,
    hint: `Override must have the same parameters as the base method`,
  }),
  methodOverrideReturnMismatch: (method: string, type: string, base: string, expected: string, got: string) => ({
    message: `Method '${method}' in '${type}' returns '${got}' but base type '${base}' returns '${expected}'`,
    hint: `Override must return the same type as the base method`,
  }),
  methodOverrideUsingMismatch: (method: string, type: string, base: string) => ({
    message: `Method '${method}' in '${type}' has different 'using' clause than in base type '${base}'`,
    hint: `Override must have the same 'using' clause as the base method`,
  }),
  inheritedTypeMissingInit: (name: string, parent: string) => ({
    message: `Type '${name}' extends '${parent}' but has no init block`,
    hint: "Types that extend another type must define an init block with super() call",
  }),
  initMissingSuperCall: (name: string) => ({
    message: `Init block in '${name}' must call super()`,
    hint: "Add super(...) call to initialize the parent type",
  }),
  superOutsideInit: () => ({
    message: "super() can only be used inside init blocks",
    hint: "Move super() call inside the init block of a type that extends another",
  }),
};

// Helper to create error message with hint
export function withHint(base: string, hint: string): string {
  return `${base}. Hint: ${hint}`;
}
