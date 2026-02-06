// @bun
// src/lexer/tokens.ts
var KEYWORDS = new Map([
  ["fn", "FN"],
  ["type", "TYPE"],
  ["let", "LET"],
  ["var", "VAR"],
  ["if", "IF"],
  ["else", "ELSE"],
  ["for", "FOR"],
  ["match", "MATCH"],
  ["return", "RETURN"],
  ["using", "USING"],
  ["with", "WITH"],
  ["interface", "INTERFACE"],
  ["import", "IMPORT"],
  ["from", "FROM"],
  ["test", "TEST"],
  ["yield", "YIELD"],
  ["defer", "DEFER"],
  ["try", "TRY"],
  ["catch", "CATCH"],
  ["throw", "THROW"],
  ["break", "BREAK"],
  ["continue", "CONTINUE"],
  ["spawn", "SPAWN"],
  ["extern", "EXTERN"],
  ["and", "AND"],
  ["or", "OR"],
  ["not", "NOT"],
  ["is", "IS"],
  ["as", "AS"],
  ["then", "THEN"],
  ["in", "IN"],
  ["true", "TRUE"],
  ["false", "FALSE"],
  ["null", "NULL"],
  ["where", "WHERE"]
]);
// src/shared/errors.ts
var RESERVED_PROPERTY_NAMES = new Set([
  "constructor",
  "__defineGetter__",
  "__defineSetter__",
  "hasOwnProperty",
  "__lookupGetter__",
  "__lookupSetter__",
  "isPrototypeOf",
  "propertyIsEnumerable",
  "toString",
  "valueOf",
  "__proto__",
  "toLocaleString",
  "prototype"
]);
var LexerErrors = {
  unterminatedString: (quote = '"') => ({
    message: "Unterminated string literal",
    hint: `Add a closing ${quote} to complete the string`
  }),
  unterminatedMultilineString: () => ({
    message: "Unterminated multiline string",
    hint: 'Add closing """ to complete the multiline string'
  }),
  unterminatedRawString: () => ({
    message: "Unterminated raw string",
    hint: 'Raw strings start with r" and must end with "'
  }),
  unterminatedRawMultilineString: () => ({
    message: "Unterminated raw multiline string",
    hint: 'Add closing """ to complete the raw multiline string'
  }),
  unterminatedByteString: () => ({
    message: "Unterminated byte string",
    hint: 'Byte strings start with b" and must end with "'
  }),
  invalidEscapeSequence: (char) => ({
    message: `Invalid escape sequence: \\${char}`,
    hint: `Valid escapes: \\n \\t \\r \\\\ \\" \\' \\0 \\x## \\u{...}. Use r"..." for raw strings`
  }),
  unexpectedCharacter: (char) => ({
    message: `Unexpected character: '${char}'`,
    hint: "Check for typos or unsupported characters"
  }),
  inconsistentIndentation: (expected, got) => ({
    message: `Inconsistent indentation: expected ${expected} spaces, got ${got}`,
    hint: "Use consistent spacing for indentation (2 or 4 spaces recommended)"
  })
};
var ParserErrors = {
  unexpectedToken: (got, context) => ({
    message: context ? `Unexpected token '${got}' ${context}` : `Unexpected token: '${got}'`,
    hint: "Check syntax or remove unexpected token"
  }),
  expectedToken: (expected, got) => ({
    message: `Expected '${expected}', got '${got}'`,
    hint: `Add '${expected}' at this position`
  }),
  expectedExpression: (got) => ({
    message: `Expected expression, got '${got}'`,
    hint: "Provide a value, variable, or expression here"
  }),
  expectedPattern: (got) => ({
    message: `Expected pattern, got '${got}'`,
    hint: "Use an identifier, literal, or destructuring pattern"
  }),
  expectedType: (got) => ({
    message: `Expected type annotation, got '${got}'`,
    hint: "Provide a type like: number, string, bool, [T], or custom type"
  }),
  expectedName: (got) => ({
    message: `Expected identifier name, got '${got}'`,
    hint: "Use a valid identifier (letters, numbers, underscores, starting with letter)"
  }),
  expectedNewline: (got) => ({
    message: `Expected newline, got '${got}'`,
    hint: "Add a line break here or check for missing statement separator"
  }),
  emptyParentheses: () => ({
    message: "Empty parentheses",
    hint: "Use () => expr for empty-parameter lambda, or remove if not needed"
  }),
  lambdaParamMustBeIdentifier: () => ({
    message: "Lambda parameter must be an identifier",
    hint: "Use simple names for lambda params: (x, y) => x + y"
  }),
  expectedTypeOrFn: (got) => ({
    message: `Expected 'type' or 'fn' declaration, got '${got}'`,
    hint: "Use 'type Name' for types or 'fn name()' for functions"
  }),
  unexpectedTokenInContext: (got) => ({
    message: `Unexpected token in 'with' expression: '${got}'`,
    hint: "Expected an expression that satisfies Closable (has close(): void)"
  })
};
var TypeErrors = {
  typeAlreadyDefined: (name) => ({
    message: `Type '${name}' is already defined`,
    hint: "Choose a different name or remove the duplicate definition"
  }),
  functionAlreadyDefined: (name) => ({
    message: `Function '${name}' is already defined`,
    hint: "Choose a different name or remove the duplicate definition"
  }),
  variableAlreadyDefined: (name) => ({
    message: `Variable '${name}' is already defined`,
    hint: "Choose a different name or use assignment (=) to update existing variable"
  }),
  unknownIdentifier: (name) => ({
    message: `Unknown identifier '${name}'`,
    hint: "Check spelling, or declare the variable before using it"
  }),
  breakOutsideLoop: () => ({
    message: "'break' statement outside of loop",
    hint: "'break' can only be used inside 'for' or 'while' loops"
  }),
  continueOutsideLoop: () => ({
    message: "'continue' statement outside of loop",
    hint: "'continue' can only be used inside 'for' or 'while' loops"
  }),
  returnOutsideFunction: () => ({
    message: "'return' statement outside of function",
    hint: "'return' can only be used inside function bodies"
  }),
  returnMissingValue: (returnType) => ({
    message: `Return statement must have a value of type '${returnType}'`,
    hint: `Add a return value: return someValue`
  }),
  yieldOutsideGenerator: () => ({
    message: "'yield' outside of generator function",
    hint: "Mark the function as 'gen fn' to use yield"
  }),
  cannotAssignToImmutable: (name) => ({
    message: `Cannot assign to immutable variable '${name}'`,
    hint: "Use 'let' instead of 'const' to allow reassignment"
  }),
  typeMismatch: (expected, got) => ({
    message: `Type '${got}' is not assignable to type '${expected}'`,
    hint: `Expected '${expected}' but got '${got}'. Check the value or type annotation`
  }),
  operatorRequiresType: (op, required, got) => ({
    message: `Operator '${op}' requires ${required}, got '${got}'`,
    hint: `Convert the value to ${required} or use a different operator`
  }),
  cannotCompare: (left, right) => ({
    message: `Cannot compare '${left}' and '${right}'`,
    hint: "Comparison operators work on values of compatible types"
  }),
  wrongArgumentCount: (expected, got) => ({
    message: `Expected ${expected} argument(s), got ${got}`,
    hint: "Check the function signature and provide the correct number of arguments"
  }),
  unknownParameter: (name, available) => ({
    message: `Unknown parameter '${name}'`,
    hint: available.length > 0 ? `Available parameters: ${available.join(", ")}` : "Check the function signature for valid parameter names"
  }),
  mixedPositionalAndNamedArguments: () => ({
    message: "Cannot mix positional and named arguments in the same call",
    hint: "Use either all positional (f(a, b)) or all named (f(a: x, b: y))"
  }),
  propertyNotExist: (prop, type) => ({
    message: `Property '${prop}' does not exist on type '${type}'`,
    hint: "Check property name spelling or verify the type has this property"
  }),
  indexTypeMismatch: (expected, got) => ({
    message: `Index type '${got}' is not assignable to '${expected}'`,
    hint: `Use a ${expected} value to index this collection`
  }),
  patternTypeMismatch: (patternKind, expected) => ({
    message: `Cannot use ${patternKind} pattern on type '${expected}'`,
    hint: `This pattern requires a compatible type`
  }),
  literalPatternMismatch: (literalType, expected) => ({
    message: `Literal of type '${literalType}' cannot match type '${expected}'`,
    hint: `The literal must be compatible with the matched type`
  }),
  unknownPatternProperty: (prop, type) => ({
    message: `Property '${prop}' does not exist on type '${type}'`,
    hint: `Check property name spelling or use a type that has this property`
  }),
  tuplePatternLengthMismatch: (expected, got) => ({
    message: `Tuple has ${expected} elements but pattern has ${got}`,
    hint: `Match the number of elements in the pattern to the tuple`
  }),
  incompatibleTypePattern: (patternType, expectedType) => ({
    message: `Type '${patternType}' is not compatible with '${expectedType}'`,
    hint: `The pattern type must be a subtype of the matched value's type`
  }),
  rangePatternRequiresNumber: (got) => ({
    message: `Range patterns require numeric type, got '${got}'`,
    hint: `Range patterns like 1..10 can only match numbers`
  }),
  guardMustBeBool: (got) => ({
    message: `Guard expression must be bool, got '${got}'`,
    hint: `The 'if' condition in a match arm must evaluate to a boolean`
  }),
  matchNotExhaustive: (missing) => ({
    message: `Match is not exhaustive. Missing cases: ${missing.join(", ")}`,
    hint: `Add the missing cases or use a wildcard '_' pattern`
  }),
  invalidTypeAssertion: (from, to) => ({
    message: `Cannot assert type '${from}' as '${to}'`,
    hint: `Type assertions require the types to be related (one must be a subtype of the other)`
  }),
  unnecessaryNullAssertion: (type) => ({
    message: `Unnecessary null assertion on non-nullable type '${type}'`,
    hint: `The expression is already non-nullable, remove the '!'`
  }),
  privateAccess: (member, type) => ({
    message: `Cannot access private member '${member}' of type '${type}'`,
    hint: `Members starting with '_' are private and can only be accessed within the defining type`
  }),
  unreachableCode: () => ({
    message: `Unreachable code detected`,
    hint: `This code will never execute. Consider removing it`
  }),
  nonIterableForLoop: (type) => ({
    message: `Cannot iterate over type '${type}'`,
    hint: `For loops require an iterable type (list, set, map, string, stream, or channel)`
  }),
  memberAccessOnFunction: () => ({
    message: `Cannot access properties on function values`,
    hint: `Functions do not have accessible properties. Call the function or use a different approach`
  }),
  memberAccessOnType: (typeName) => ({
    message: `Cannot access properties on type '${typeName}' directly`,
    hint: `Use Type() constructor to create an instance, then access properties on the instance`
  }),
  reservedPropertyName: (name) => ({
    message: `Property name '${name}' is reserved and cannot be used`,
    hint: `This name conflicts with JavaScript Object prototype methods. Choose a different name`
  }),
  indexAccessOnInvalidType: (type) => ({
    message: `Index access is not allowed on type '${type}'`,
    hint: `Index access [] is only allowed on list, map, and string types`
  }),
  operationNotAllowedOnUnknown: (operation) => ({
    message: operation ? `Operation '${operation}' is not allowed on type 'unknown'` : "Operations are not allowed on type 'unknown'",
    hint: "Narrow the value first with 'x as Type' before using it"
  }),
  genericParamMustBeIdentifier: () => ({
    message: `Generic type parameter must be an identifier`,
    hint: `Use a simple type name like T, K, V, etc.`
  }),
  methodRequiresBody: (methodName, typeName) => ({
    message: `Method '${methodName}' on type '${typeName}' must have a body`,
    hint: `Concrete types require method implementations. Use 'interface' for method signatures only`
  })
};

// src/lexer/lexer.ts
class LexerError extends Error {
  loc;
  hint;
  constructor(message, loc, hint) {
    super(`${message} at line ${loc.line}, column ${loc.column}`);
    this.loc = loc;
    this.hint = hint;
    this.name = "LexerError";
  }
}

class Lexer {
  source;
  pos = 0;
  line = 1;
  column = 1;
  tokens = [];
  indentStack = [0];
  atLineStart = true;
  pendingTokens = [];
  pendingComment;
  pendingCommentLine = 0;
  constructor(source) {
    this.source = source;
  }
  tokenize() {
    while (!this.isAtEnd()) {
      this.scanToken();
    }
    while (this.indentStack.length > 1) {
      this.indentStack.pop();
      this.tokens.push(this.makeToken("DEDENT", null, ""));
    }
    this.tokens.push(this.makeToken("EOF", null, ""));
    return this.tokens;
  }
  scanToken() {
    if (this.atLineStart) {
      this.handleIndentation();
      this.atLineStart = false;
      if (this.isAtEnd())
        return;
    }
    const char = this.peek();
    if (char === " " || char === "\t") {
      this.advance();
      return;
    }
    if (char === "/" && this.peekNext() === "/") {
      this.skipComment();
      return;
    }
    if (char === `
`) {
      this.handleNewline();
      return;
    }
    if (char === "\r") {
      this.advance();
      if (this.peek() === `
`) {
        this.handleNewline();
      }
      return;
    }
    if (char === '"') {
      this.scanString();
      return;
    }
    if (char === "r" && this.peekNext() === '"') {
      this.scanRawString();
      return;
    }
    if (char === "b" && this.peekNext() === '"') {
      this.scanByteString();
      return;
    }
    if (this.isDigit(char)) {
      this.scanNumber();
      return;
    }
    if (this.isAlpha(char)) {
      this.scanIdentifier();
      return;
    }
    this.scanOperator();
  }
  handleIndentation() {
    let indent = 0;
    while (this.peek() === " ") {
      indent++;
      this.advance();
    }
    while (this.peek() === "\t") {
      indent += 2;
      this.advance();
    }
    if (this.peek() === `
` || this.peek() === "\r" || this.peek() === "/" && this.peekNext() === "/") {
      return;
    }
    if (this.isAtEnd())
      return;
    const currentIndent = this.indentStack[this.indentStack.length - 1];
    if (indent > currentIndent) {
      this.indentStack.push(indent);
      this.tokens.push(this.makeToken("INDENT", null, ""));
    } else if (indent < currentIndent) {
      while (this.indentStack.length > 1 && this.indentStack[this.indentStack.length - 1] > indent) {
        this.indentStack.pop();
        this.tokens.push(this.makeToken("DEDENT", null, ""));
      }
      if (this.indentStack[this.indentStack.length - 1] !== indent) {
        const err = LexerErrors.inconsistentIndentation(this.indentStack[this.indentStack.length - 1], indent);
        throw new LexerError(err.message, this.currentLoc(), err.hint);
      }
    }
  }
  handleNewline() {
    const lastToken = this.tokens[this.tokens.length - 1];
    if (!lastToken || lastToken.type !== "NEWLINE" && lastToken.type !== "INDENT") {
      this.tokens.push(this.makeToken("NEWLINE", null, `
`));
    }
    this.advance();
    this.line++;
    this.column = 1;
    this.atLineStart = true;
  }
  skipComment() {
    this.advance();
    this.advance();
    const commentStart = this.pos;
    while (!this.isAtEnd() && this.peek() !== `
`) {
      this.advance();
    }
    const commentText = this.source.slice(commentStart, this.pos).trim();
    if (this.pendingComment && this.line === this.pendingCommentLine + 1) {
      this.pendingComment += `
` + commentText;
    } else {
      this.pendingComment = commentText;
    }
    this.pendingCommentLine = this.line;
  }
  scanString() {
    const startLoc = this.currentLoc();
    const startPos = this.pos;
    if (this.peek() === '"' && this.peekNext() === '"' && this.peekAt(2) === '"') {
      this.scanMultilineString();
      return;
    }
    this.advance();
    let value = "";
    let hasInterpolation = false;
    while (!this.isAtEnd() && this.peek() !== '"') {
      if (this.peek() === `
`) {
        const err = LexerErrors.unterminatedString();
        throw new LexerError(err.message, startLoc, err.hint);
      }
      if (this.peek() === "\\") {
        value += this.scanEscapeSequence();
      } else if (this.peek() === "{") {
        hasInterpolation = true;
        value += this.advance();
      } else {
        value += this.advance();
      }
    }
    if (this.isAtEnd()) {
      const err = LexerErrors.unterminatedString();
      throw new LexerError(err.message, startLoc, err.hint);
    }
    this.advance();
    const raw = this.source.slice(startPos, this.pos);
    this.tokens.push(this.makeToken("STRING", value, raw, startLoc));
  }
  scanMultilineString() {
    const startLoc = this.currentLoc();
    const startPos = this.pos;
    this.advance();
    this.advance();
    this.advance();
    let value = "";
    while (!this.isAtEnd()) {
      if (this.peek() === '"' && this.peekNext() === '"' && this.peekAt(2) === '"') {
        this.advance();
        this.advance();
        this.advance();
        const raw = this.source.slice(startPos, this.pos);
        this.tokens.push(this.makeToken("STRING", value, raw, startLoc));
        return;
      }
      if (this.peek() === `
`) {
        value += `
`;
        this.advance();
        this.line++;
        this.column = 1;
      } else if (this.peek() === "\\") {
        value += this.scanEscapeSequence();
      } else {
        value += this.advance();
      }
    }
    const err = LexerErrors.unterminatedMultilineString();
    throw new LexerError(err.message, startLoc, err.hint);
  }
  scanRawString() {
    const startLoc = this.currentLoc();
    const startPos = this.pos;
    this.advance();
    if (this.peek() === '"' && this.peekNext() === '"' && this.peekAt(2) === '"') {
      this.advance();
      this.advance();
      this.advance();
      let value2 = "";
      while (!this.isAtEnd()) {
        if (this.peek() === '"' && this.peekNext() === '"' && this.peekAt(2) === '"') {
          this.advance();
          this.advance();
          this.advance();
          const raw2 = this.source.slice(startPos, this.pos);
          this.tokens.push(this.makeToken("STRING", value2, raw2, startLoc));
          return;
        }
        if (this.peek() === `
`) {
          value2 += `
`;
          this.advance();
          this.line++;
          this.column = 1;
        } else {
          value2 += this.advance();
        }
      }
      const err = LexerErrors.unterminatedRawMultilineString();
      throw new LexerError(err.message, startLoc, err.hint);
    }
    this.advance();
    let value = "";
    while (!this.isAtEnd() && this.peek() !== '"') {
      if (this.peek() === `
`) {
        const err = LexerErrors.unterminatedRawString();
        throw new LexerError(err.message, startLoc, err.hint);
      }
      value += this.advance();
    }
    if (this.isAtEnd()) {
      const err = LexerErrors.unterminatedRawString();
      throw new LexerError(err.message, startLoc, err.hint);
    }
    this.advance();
    const raw = this.source.slice(startPos, this.pos);
    this.tokens.push(this.makeToken("STRING", value, raw, startLoc));
  }
  scanByteString() {
    const startLoc = this.currentLoc();
    const startPos = this.pos;
    this.advance();
    this.advance();
    let value = "";
    while (!this.isAtEnd() && this.peek() !== '"') {
      if (this.peek() === `
`) {
        const err = LexerErrors.unterminatedByteString();
        throw new LexerError(err.message, startLoc, err.hint);
      }
      if (this.peek() === "\\") {
        value += this.scanEscapeSequence();
      } else {
        value += this.advance();
      }
    }
    if (this.isAtEnd()) {
      const err = LexerErrors.unterminatedByteString();
      throw new LexerError(err.message, startLoc, err.hint);
    }
    this.advance();
    const raw = this.source.slice(startPos, this.pos);
    this.tokens.push(this.makeToken("STRING", value, raw, startLoc));
  }
  scanEscapeSequence() {
    this.advance();
    const char = this.advance();
    switch (char) {
      case "n":
        return `
`;
      case "t":
        return "\t";
      case "r":
        return "\r";
      case "\\":
        return "\\";
      case '"':
        return '"';
      case "{":
        return "{";
      case "}":
        return "}";
      case "u": {
        if (this.peek() === "{") {
          this.advance();
          let hex = "";
          while (this.peek() !== "}" && !this.isAtEnd()) {
            hex += this.advance();
          }
          this.advance();
          return String.fromCodePoint(parseInt(hex, 16));
        } else {
          let hex = "";
          for (let i = 0;i < 4 && !this.isAtEnd(); i++) {
            hex += this.advance();
          }
          return String.fromCharCode(parseInt(hex, 16));
        }
      }
      case "x": {
        let hex = "";
        for (let i = 0;i < 2 && !this.isAtEnd(); i++) {
          hex += this.advance();
        }
        return String.fromCharCode(parseInt(hex, 16));
      }
      default:
        const err = LexerErrors.invalidEscapeSequence(char);
        throw new LexerError(err.message, this.currentLoc(), err.hint);
    }
  }
  scanNumber() {
    const startLoc = this.currentLoc();
    const startPos = this.pos;
    if (this.peek() === "0") {
      const next = this.peekNext();
      if (next === "x" || next === "X") {
        this.scanHexNumber(startLoc, startPos);
        return;
      }
      if (next === "b" || next === "B") {
        this.scanBinaryNumber(startLoc, startPos);
        return;
      }
    }
    while (this.isDigit(this.peek()) || this.peek() === "_") {
      this.advance();
    }
    if (this.peek() === "." && this.isDigit(this.peekNext())) {
      this.advance();
      while (this.isDigit(this.peek()) || this.peek() === "_") {
        this.advance();
      }
    }
    if (this.peek() === "e" || this.peek() === "E") {
      this.advance();
      if (this.peek() === "+" || this.peek() === "-") {
        this.advance();
      }
      while (this.isDigit(this.peek()) || this.peek() === "_") {
        this.advance();
      }
    }
    const raw = this.source.slice(startPos, this.pos);
    const value = parseFloat(raw.replace(/_/g, ""));
    this.tokens.push(this.makeToken("NUMBER", value, raw, startLoc));
  }
  scanHexNumber(startLoc, startPos) {
    this.advance();
    this.advance();
    while (this.isHexDigit(this.peek()) || this.peek() === "_") {
      this.advance();
    }
    const raw = this.source.slice(startPos, this.pos);
    const hexPart = raw.slice(2).replace(/_/g, "");
    const value = parseInt(hexPart, 16);
    this.tokens.push(this.makeToken("NUMBER", value, raw, startLoc));
  }
  scanBinaryNumber(startLoc, startPos) {
    this.advance();
    this.advance();
    while (this.peek() === "0" || this.peek() === "1" || this.peek() === "_") {
      this.advance();
    }
    const raw = this.source.slice(startPos, this.pos);
    const binPart = raw.slice(2).replace(/_/g, "");
    const value = parseInt(binPart, 2);
    this.tokens.push(this.makeToken("NUMBER", value, raw, startLoc));
  }
  scanIdentifier() {
    const startLoc = this.currentLoc();
    const startPos = this.pos;
    while (this.isAlphaNumeric(this.peek())) {
      this.advance();
    }
    const raw = this.source.slice(startPos, this.pos);
    const type = KEYWORDS.get(raw) ?? "IDENTIFIER";
    const value = type === "TRUE" ? true : type === "FALSE" ? false : type === "NULL" ? null : raw;
    this.tokens.push(this.makeToken(type, value, raw, startLoc));
  }
  scanOperator() {
    const startLoc = this.currentLoc();
    const char = this.advance();
    let type;
    let raw = char;
    switch (char) {
      case "+":
        if (this.match("=")) {
          type = "PLUS_ASSIGN";
          raw = "+=";
        } else {
          type = "PLUS";
        }
        break;
      case "-":
        if (this.match("=")) {
          type = "MINUS_ASSIGN";
          raw = "-=";
        } else {
          type = "MINUS";
        }
        break;
      case "*":
        if (this.match("=")) {
          type = "STAR_ASSIGN";
          raw = "*=";
        } else {
          type = "STAR";
        }
        break;
      case "/":
        if (this.match("=")) {
          type = "SLASH_ASSIGN";
          raw = "/=";
        } else {
          type = "SLASH";
        }
        break;
      case "%":
        if (this.match("=")) {
          type = "PERCENT_ASSIGN";
          raw = "%=";
        } else {
          type = "PERCENT";
        }
        break;
      case "^":
        type = "CARET";
        break;
      case "=":
        if (this.match("=")) {
          type = "EQ";
          raw = "==";
        } else if (this.match(">")) {
          type = "ARROW";
          raw = "=>";
        } else {
          type = "ASSIGN";
        }
        break;
      case "!":
        if (this.match("=")) {
          type = "NEQ";
          raw = "!=";
        } else {
          type = "BANG";
        }
        break;
      case "<":
        if (this.match("=")) {
          type = "LTE";
          raw = "<=";
        } else {
          type = "LT";
        }
        break;
      case ">":
        if (this.match("=")) {
          type = "GTE";
          raw = ">=";
        } else {
          type = "GT";
        }
        break;
      case "?":
        if (this.match("?")) {
          type = "NULLISH";
          raw = "??";
        } else if (this.match(".")) {
          type = "OPTIONAL";
          raw = "?.";
        } else {
          type = "QUESTION";
        }
        break;
      case "|":
        type = "PIPE";
        break;
      case ".":
        if (this.match(".")) {
          if (this.match(".")) {
            type = "SPREAD";
            raw = "...";
          } else {
            type = "DOTDOT";
            raw = "..";
          }
        } else {
          type = "DOT";
        }
        break;
      case ":":
        type = "COLON";
        break;
      case ",":
        type = "COMMA";
        break;
      case "(":
        type = "LPAREN";
        break;
      case ")":
        type = "RPAREN";
        break;
      case "[":
        type = "LBRACKET";
        break;
      case "]":
        type = "RBRACKET";
        break;
      case "{":
        type = "LBRACE";
        break;
      case "}":
        type = "RBRACE";
        break;
      default:
        const err = LexerErrors.unexpectedCharacter(char);
        throw new LexerError(err.message, startLoc, err.hint);
    }
    this.tokens.push(this.makeToken(type, raw, raw, startLoc));
  }
  peek() {
    if (this.isAtEnd())
      return "\x00";
    return this.source[this.pos];
  }
  peekNext() {
    if (this.pos + 1 >= this.source.length)
      return "\x00";
    return this.source[this.pos + 1];
  }
  peekAt(offset) {
    if (this.pos + offset >= this.source.length)
      return "\x00";
    return this.source[this.pos + offset];
  }
  advance() {
    const char = this.source[this.pos];
    this.pos++;
    this.column++;
    return char;
  }
  match(expected) {
    if (this.isAtEnd())
      return false;
    if (this.source[this.pos] !== expected)
      return false;
    this.pos++;
    this.column++;
    return true;
  }
  isAtEnd() {
    return this.pos >= this.source.length;
  }
  isDigit(char) {
    return char >= "0" && char <= "9";
  }
  isHexDigit(char) {
    return char >= "0" && char <= "9" || char >= "a" && char <= "f" || char >= "A" && char <= "F";
  }
  isAlpha(char) {
    return char >= "a" && char <= "z" || char >= "A" && char <= "Z" || char === "_";
  }
  isAlphaNumeric(char) {
    return this.isAlpha(char) || this.isDigit(char);
  }
  currentLoc() {
    return { line: this.line, column: this.column, offset: this.pos };
  }
  makeToken(type, value, raw, loc) {
    const token = { type, value, raw, loc: loc ?? this.currentLoc() };
    if (this.pendingComment && type !== "NEWLINE" && type !== "INDENT" && type !== "DEDENT" && type !== "EOF") {
      if ((loc?.line ?? this.line) - this.pendingCommentLine <= 1) {
        token.leadingComment = this.pendingComment;
      }
      this.pendingComment = undefined;
    }
    return token;
  }
}
// src/parser/parser.ts
var KEYWORD_TOKEN_TYPES = new Set(KEYWORDS.values());

class ParseError extends Error {
  token;
  hint;
  constructor(message, token, hint) {
    super(`${message} at line ${token.loc.line}, column ${token.loc.column}`);
    this.token = token;
    this.hint = hint;
    this.name = "ParseError";
  }
}
class Parser {
  tokens = [];
  pos = 0;
  prefixParsers = new Map;
  infixParsers = new Map;
  precedences = new Map;
  constructor(source) {
    this.tokens = new Lexer(source).tokenize();
    this.registerParsers();
  }
  registerParsers() {
    this.prefix("NUMBER", () => this.literal());
    this.prefix("STRING", () => this.literal());
    this.prefix("TRUE", () => this.literal());
    this.prefix("FALSE", () => this.literal());
    this.prefix("NULL", () => this.literal());
    this.prefix("IDENTIFIER", () => this.identifier());
    this.prefix("LPAREN", () => this.groupOrLambda());
    this.prefix("LBRACKET", () => this.listExpr());
    this.prefix("LT", () => this.setExpr());
    this.prefix("LBRACE", () => this.mapExpr());
    this.prefix("MINUS", () => this.unary());
    this.prefix("NOT", () => this.unary());
    this.prefix("BANG", () => this.unary());
    this.prefix("IF", () => this.ifExpr());
    this.prefix("MATCH", () => this.matchExpr());
    this.prefix("SPAWN", () => this.spawnExpr());
    this.infix("PLUS", 9 /* TERM */, (l) => this.binary(l));
    this.infix("MINUS", 9 /* TERM */, (l) => this.binary(l));
    this.infix("STAR", 10 /* FACTOR */, (l) => this.binary(l));
    this.infix("SLASH", 10 /* FACTOR */, (l) => this.binary(l));
    this.infix("PERCENT", 10 /* FACTOR */, (l) => this.binary(l));
    this.infix("CARET", 11 /* POWER */, (l) => this.binaryRight(l));
    this.infix("EQ", 7 /* COMPARISON */, (l) => this.binary(l));
    this.infix("NEQ", 7 /* COMPARISON */, (l) => this.binary(l));
    this.infix("LT", 7 /* COMPARISON */, (l) => this.binary(l));
    this.infix("GT", 7 /* COMPARISON */, (l) => this.binary(l));
    this.infix("LTE", 7 /* COMPARISON */, (l) => this.binary(l));
    this.infix("GTE", 7 /* COMPARISON */, (l) => this.binary(l));
    this.infix("AND", 5 /* AND */, (l) => this.binary(l));
    this.infix("OR", 4 /* OR */, (l) => this.binary(l));
    this.infix("IS", 7 /* COMPARISON */, (l) => this.isExpr(l));
    this.infix("AS", 7 /* COMPARISON */, (l) => this.asExpr(l));
    this.infix("NULLISH", 3 /* NULLISH */, (l) => this.binary(l));
    this.infix("PIPE", 2 /* PIPE */, (l) => this.pipeExpr(l));
    this.infix("DOTDOT", 8 /* RANGE */, (l) => this.rangeExpr(l));
    this.infix("LPAREN", 13 /* CALL */, (l) => this.callExpr(l));
    this.infix("LBRACKET", 13 /* CALL */, (l) => this.indexExpr(l, false));
    this.infix("DOT", 13 /* CALL */, (l) => this.memberExpr(l, false));
    this.infix("OPTIONAL", 13 /* CALL */, (l) => {
      if (this.check("LBRACKET")) {
        this.advance();
        return this.indexExpr(l, true);
      }
      return this.memberExpr(l, true);
    });
    this.infix("BANG", 13 /* CALL */, (l) => this.nullAssertion(l));
  }
  prefix(type, fn) {
    this.prefixParsers.set(type, fn.bind(this));
  }
  infix(type, prec, fn) {
    this.precedences.set(type, prec);
    this.infixParsers.set(type, fn.bind(this));
  }
  parse() {
    const body = [];
    this.skipNewlines();
    while (!this.isAtEnd()) {
      body.push(this.declaration());
      this.skipNewlines();
      while (this.match("DEDENT")) {}
    }
    return {
      kind: "Program",
      body,
      loc: body[0]?.loc ?? { line: 1, column: 1, offset: 0 }
    };
  }
  parseExpression() {
    this.skipNewlines();
    return this.expression();
  }
  parseStatement() {
    this.skipNewlines();
    return this.statement();
  }
  declaration() {
    const token = this.peek();
    switch (token.type) {
      case "IMPORT":
        return this.importDecl();
      case "FN":
        return this.fnDecl();
      case "EXTERN":
        if (this.peekNext().type === "TYPE") {
          const externDoc = this.current().leadingComment;
          this.advance();
          return this.typeDecl(true, externDoc);
        }
        return this.externFnDecl();
      case "TYPE":
        return this.typeDecl(false);
      case "INTERFACE":
        return this.interfaceDecl();
      case "TEST":
        return this.testDecl();
      case "IDENTIFIER":
        return this.statement();
      default:
        return this.statement();
    }
  }
  importDecl() {
    const loc = this.current().loc;
    this.expect("IMPORT");
    this.expect("LBRACE");
    const names = [];
    while (!this.check("RBRACE")) {
      const name = this.expectIdentifier();
      let alias;
      if (this.match("AS")) {
        alias = this.expectIdentifier();
      }
      names.push({ name, alias });
      if (!this.check("RBRACE")) {
        this.expect("COMMA");
      }
    }
    this.expect("RBRACE");
    this.expect("FROM");
    const source = this.expectString();
    return { kind: "ImportDecl", names, source, loc };
  }
  fnDecl() {
    const doc = this.current().leadingComment;
    const loc = this.current().loc;
    this.expect("FN");
    const name = this.expectIdentifier();
    const typeParams = this.check("LBRACKET") ? this.parseTypeParams() : undefined;
    const params = this.parseParams();
    const returnType = this.match("COLON") ? this.parseType() : undefined;
    const using = this.check("USING") ? this.parseUsing() : undefined;
    this.expectNewline();
    const body = this.parseBlock();
    const isGenerator = this.containsYield(body);
    return { kind: "FnDecl", name, typeParams, params, returnType, using, body, isGenerator, loc, doc };
  }
  externFnDecl() {
    const doc = this.current().leadingComment;
    const loc = this.current().loc;
    this.expect("EXTERN");
    this.expect("FN");
    const name = this.expectIdentifierOrKeyword();
    const typeParams = this.check("LBRACKET") ? this.parseTypeParams() : undefined;
    const params = this.parseParams();
    const returnType = this.match("COLON") ? this.parseType() : undefined;
    return { kind: "ExternFnDecl", name, typeParams, params, returnType, loc, doc };
  }
  expectIdentifierOrKeyword() {
    const token = this.advance();
    if (token.type === "IDENTIFIER" || token.value !== null && typeof token.value === "string") {
      return token.raw;
    }
    const err = ParserErrors.expectedToken("IDENTIFIER", token.type);
    throw new ParseError(err.message, token, err.hint);
  }
  parseParams() {
    this.expect("LPAREN");
    const params = [];
    while (!this.check("RPAREN")) {
      const paramLoc = this.current().loc;
      let rest = false;
      if (this.match("SPREAD")) {
        rest = true;
      }
      const name = this.expectIdentifier();
      let optional = false;
      let type;
      let defaultValue;
      if (this.match("QUESTION")) {
        optional = true;
      }
      if (this.match("COLON")) {
        type = this.parseType();
      }
      if (this.match("ASSIGN")) {
        defaultValue = this.expression();
        optional = true;
      }
      params.push({ kind: "Parameter", name, type, optional, defaultValue, rest, loc: paramLoc });
      if (!this.check("RPAREN")) {
        this.expect("COMMA");
      }
    }
    this.expect("RPAREN");
    return params;
  }
  parseUsing() {
    const loc = this.current().loc;
    this.expect("USING");
    this.expect("LPAREN");
    const bindings = [];
    while (!this.check("RPAREN")) {
      const bindingLoc = this.current().loc;
      const first = this.expectIdentifier();
      if (this.match("COLON")) {
        const type = this.parseType();
        bindings.push({ kind: "UsingBinding", name: first, type, loc: bindingLoc });
      } else {
        bindings.push({ kind: "UsingBinding", type: { kind: "NamedType", name: first, loc: this.current().loc }, loc: bindingLoc });
      }
      if (!this.check("RPAREN")) {
        this.expect("COMMA");
      }
    }
    this.expect("RPAREN");
    return { kind: "UsingClause", bindings, loc };
  }
  typeDecl(isExtern = false, externDoc) {
    const doc = externDoc ?? this.current().leadingComment;
    const loc = this.current().loc;
    this.expect("TYPE");
    const name = this.expectIdentifier();
    const typeParams = this.check("LBRACKET") ? this.parseTypeParams() : undefined;
    if (this.match("ASSIGN")) {
      const firstType = this.parseType();
      if (this.check("OR")) {
        const types = [firstType];
        while (this.match("OR")) {
          types.push(this.parseType());
        }
        return {
          kind: "TypeDecl",
          name,
          typeParams,
          body: { kind: "TypeBody", members: [], loc },
          loc,
          alias: types,
          doc
        };
      }
      return {
        kind: "TypeDecl",
        name,
        typeParams,
        alias: [firstType],
        body: { kind: "TypeBody", members: [], loc },
        loc,
        doc
      };
    }
    const using = this.check("USING") ? this.parseUsing() : undefined;
    let where;
    if (this.check("WHERE")) {
      where = this.parseWhere();
    }
    let body;
    if (this.match("NEWLINE") && this.check("INDENT")) {
      body = this.parseTypeBody(isExtern);
    } else {
      body = { kind: "TypeBody", members: [], loc };
    }
    return { kind: "TypeDecl", name, typeParams, using, where, body, loc, isExtern: isExtern || undefined, doc };
  }
  interfaceDecl() {
    const doc = this.current().leadingComment;
    const loc = this.current().loc;
    this.expect("INTERFACE");
    const name = this.expectIdentifier();
    const typeParams = this.check("LBRACKET") ? this.parseTypeParams() : undefined;
    let body;
    if (this.match("NEWLINE") && this.check("INDENT")) {
      body = this.parseInterfaceBody();
    } else {
      body = { kind: "InterfaceBody", members: [], loc: this.current().loc };
    }
    return { kind: "InterfaceDecl", name, typeParams, body, loc, doc };
  }
  parseInterfaceBody() {
    const loc = this.current().loc;
    const members = [];
    this.expect("INDENT");
    this.skipNewlines();
    while (!this.check("DEDENT") && !this.isAtEnd()) {
      if (this.check("FN") || this.check("EXTERN")) {
        members.push(this.parseMethodDecl(false, true));
      } else if (this.isEmbeddedType()) {
        members.push(this.parseEmbeddedInterface());
      } else {
        const name = this.peek().value;
        throw new ParseError(`Unexpected token in interface body: expected method signature or embedded interface name, got '${name}'`, this.current(), "Interfaces contain only fn signatures and embedded interface names");
      }
      this.skipNewlines();
    }
    this.expect("DEDENT");
    return { kind: "InterfaceBody", members, loc };
  }
  parseEmbeddedInterface() {
    const loc = this.current().loc;
    const name = this.expectIdentifier();
    return { kind: "EmbeddedInterfaceDecl", name, loc };
  }
  parseTypeParams() {
    this.expect("LBRACKET");
    const params = [];
    while (!this.check("RBRACKET")) {
      const paramLoc = this.current().loc;
      const name = this.expectIdentifier();
      let constraint;
      if (this.match("COLON")) {
        constraint = this.parseType();
      }
      params.push({ kind: "TypeParam", name, constraint, loc: paramLoc });
      if (!this.check("RBRACKET")) {
        this.expect("COMMA");
      }
    }
    this.expect("RBRACKET");
    return params;
  }
  parseWhere() {
    const clauses = [];
    this.expect("WHERE");
    const loc = this.current().loc;
    const param = this.expectIdentifier();
    this.expect("COLON");
    const constraint = this.parseType();
    clauses.push({ kind: "WhereClause", param, constraint, loc });
    while (this.match("COMMA")) {
      const clauseLoc = this.current().loc;
      const p = this.expectIdentifier();
      this.expect("COLON");
      const c = this.parseType();
      clauses.push({ kind: "WhereClause", param: p, constraint: c, loc: clauseLoc });
    }
    return clauses;
  }
  parseTypeBody(isExternType = false) {
    const loc = this.current().loc;
    const members = [];
    this.expect("INDENT");
    this.skipNewlines();
    while (!this.check("DEDENT") && !this.isAtEnd()) {
      if (this.check("FN") || this.check("EXTERN")) {
        members.push(this.parseMethodDecl(isExternType));
      } else if (this.isEmbeddedType()) {
        members.push(this.parseEmbeddedType());
      } else {
        members.push(this.parseFieldDecl());
      }
      this.skipNewlines();
    }
    this.expect("DEDENT");
    return { kind: "TypeBody", members, loc };
  }
  parseFieldDecl() {
    const doc = this.current().leadingComment;
    const loc = this.current().loc;
    const name = this.expectIdentifier();
    let optional = false;
    if (this.match("QUESTION")) {
      optional = true;
    }
    let type;
    if (this.match("COLON")) {
      if (this.check("LPAREN")) {
        const next = this.peekNext();
        if (next.type === "RPAREN") {
          this.advance();
          this.advance();
          this.expect("ARROW");
          const body = this.expression();
          const lambda = { kind: "LambdaExpr", params: [], body, loc };
          return { kind: "FieldDecl", name, optional, computed: true, defaultValue: lambda, loc, doc };
        }
      }
      type = this.parseType();
    }
    let defaultValue;
    if (this.match("ASSIGN")) {
      defaultValue = this.expression();
    }
    return { kind: "FieldDecl", name, type, optional, defaultValue, computed: false, loc, doc };
  }
  isEmbeddedType() {
    if (!this.check("IDENTIFIER"))
      return false;
    const name = this.peek().value;
    if (!name || name.length === 0)
      return false;
    const firstChar = name[0];
    if (firstChar !== firstChar.toUpperCase() || firstChar === firstChar.toLowerCase()) {
      return false;
    }
    const next = this.peekNext();
    return next.type !== "COLON" && next.type !== "QUESTION";
  }
  parseEmbeddedType() {
    const loc = this.current().loc;
    const name = this.expectIdentifier();
    return {
      kind: "FieldDecl",
      name,
      type: { kind: "NamedType", name, loc },
      optional: false,
      computed: false,
      embedded: true,
      loc
    };
  }
  parseMethodDecl(implicitExtern = false, skipBody = false) {
    const doc = this.current().leadingComment;
    const loc = this.current().loc;
    const explicitExtern = this.match("EXTERN");
    const isExtern = implicitExtern || explicitExtern;
    this.expect("FN");
    const name = this.expectIdentifier();
    const typeParams = this.check("LBRACKET") ? this.parseTypeParams() : undefined;
    const params = this.parseParams();
    const returnType = this.match("COLON") ? this.parseType() : undefined;
    const using = this.check("USING") ? this.parseUsing() : undefined;
    let body;
    if (!skipBody && !isExtern && this.match("NEWLINE") && this.check("INDENT")) {
      body = this.parseBlock();
    }
    return { kind: "MethodDecl", name, typeParams, params, returnType, using, body, isExtern: isExtern || undefined, loc, doc };
  }
  testDecl() {
    const loc = this.current().loc;
    this.expect("TEST");
    const description = this.expectString();
    let withClause;
    if (this.match("WITH")) {
      withClause = this.expression();
    }
    this.expectNewline();
    const body = this.parseBlock();
    return { kind: "TestDecl", description, withClause, body, loc };
  }
  statement() {
    const token = this.peek();
    switch (token.type) {
      case "LET":
        return this.letStmt();
      case "VAR":
        return this.varStmt();
      case "IF":
        return this.ifStmt();
      case "FOR":
        return this.forStmt();
      case "MATCH":
        return this.matchStmt();
      case "RETURN":
        return this.returnStmt();
      case "YIELD":
        return this.yieldStmt();
      case "BREAK":
        return this.breakStmt();
      case "CONTINUE":
        return this.continueStmt();
      case "DEFER":
        return this.deferStmt();
      case "TRY":
        return this.tryStmt();
      case "THROW":
        return this.throwStmt();
      case "WITH":
        return this.withStmt();
      case "FN":
        return this.fnDecl();
      case "TYPE":
        return this.typeDecl();
      default:
        return this.exprOrAssignStmt();
    }
  }
  letStmt() {
    const loc = this.current().loc;
    this.expect("LET");
    const pattern = this.parsePattern();
    const type = this.match("COLON") ? this.parseType() : undefined;
    this.expect("ASSIGN");
    const value = this.expression();
    return { kind: "LetStmt", pattern, type, value, loc };
  }
  varStmt() {
    const loc = this.current().loc;
    this.expect("VAR");
    const name = this.expectIdentifier();
    const type = this.match("COLON") ? this.parseType() : undefined;
    this.expect("ASSIGN");
    const value = this.expression();
    return { kind: "VarStmt", name, type, value, loc };
  }
  ifStmt() {
    const loc = this.current().loc;
    this.expect("IF");
    if (this.check("LET")) {
      return this.guardStmt(loc);
    }
    const condition = this.expression();
    if (this.match("THEN")) {
      const isStatement = this.check("RETURN") || this.check("BREAK") || this.check("CONTINUE") || this.check("THROW") || this.check("LET") || this.check("VAR");
      if (isStatement) {
        const then3 = this.statement();
        return { kind: "IfStmt", condition, then: then3, elseIfs: [], loc };
      }
      const thenExpr = this.expression();
      if (this.check("ELSE")) {
        this.advance();
        const elseExpr = this.expression();
        const ifExpr = {
          kind: "IfExpr",
          condition,
          then: thenExpr,
          else: elseExpr,
          loc
        };
        return { kind: "ExprStmt", expr: ifExpr, loc };
      }
      const then2 = { kind: "ExprStmt", expr: thenExpr, loc: thenExpr.loc };
      return { kind: "IfStmt", condition, then: then2, elseIfs: [], loc };
    }
    this.expectNewline();
    const then = this.parseBlock();
    const elseIfs = [];
    let elseBlock;
    while (this.check("ELSE")) {
      this.advance();
      if (this.match("IF")) {
        const elifCond = this.expression();
        this.expectNewline();
        const elifBody = this.parseBlock();
        elseIfs.push({ condition: elifCond, body: elifBody });
      } else {
        this.expectNewline();
        elseBlock = this.parseBlock();
        break;
      }
    }
    return { kind: "IfStmt", condition, then, elseIfs, else: elseBlock, loc };
  }
  guardStmt(loc) {
    this.expect("LET");
    const pattern = this.parsePattern();
    this.expect("ASSIGN");
    const condition = this.expression();
    this.expect("ELSE");
    let elseReturn;
    if (this.check("RETURN") || this.check("THROW")) {
      const stmtKind = this.peek().type;
      this.advance();
      elseReturn = this.check("NEWLINE") || this.check("EOF") ? { kind: "Identifier", name: "null", loc } : this.expression();
    } else {
      elseReturn = this.expression();
    }
    return {
      kind: "IfStmt",
      condition,
      pattern,
      elseReturn,
      then: { kind: "Block", statements: [], loc },
      elseIfs: [],
      loc
    };
  }
  forStmt() {
    const loc = this.current().loc;
    this.expect("FOR");
    if (this.check("NEWLINE")) {
      this.advance();
      const body2 = this.parseBlock();
      return { kind: "ForStmt", body: body2, loc };
    }
    const pattern = this.parsePattern();
    this.expect("IN");
    const iterable = this.expression();
    this.expectNewline();
    const body = this.parseBlock();
    return { kind: "ForStmt", pattern, iterable, body, loc };
  }
  matchStmt() {
    const loc = this.current().loc;
    this.expect("MATCH");
    const value = this.expression();
    this.expectNewline();
    this.expect("INDENT");
    this.skipNewlines();
    const arms = [];
    while (!this.check("DEDENT") && !this.isAtEnd()) {
      arms.push(this.parseMatchArm());
      this.skipNewlines();
    }
    this.expect("DEDENT");
    return { kind: "MatchStmt", value, arms, loc };
  }
  parseMatchArm() {
    const loc = this.current().loc;
    const pattern = this.parsePattern();
    let guard;
    if (this.check("IF")) {
      this.advance();
      guard = this.parseGuardExpression();
    }
    this.expect("ARROW");
    const body = this.expression();
    return { kind: "MatchArm", pattern, guard, body, loc };
  }
  parseGuardExpression() {
    return this.expression(1 /* ASSIGNMENT */ + 1);
  }
  returnStmt() {
    const loc = this.current().loc;
    this.expect("RETURN");
    let value;
    if (!this.check("NEWLINE") && !this.check("DEDENT") && !this.isAtEnd()) {
      value = this.expression();
    }
    return { kind: "ReturnStmt", value, loc };
  }
  yieldStmt() {
    const loc = this.current().loc;
    this.expect("YIELD");
    const value = this.expression();
    return { kind: "YieldStmt", value, loc };
  }
  breakStmt() {
    const loc = this.current().loc;
    this.expect("BREAK");
    return { kind: "BreakStmt", loc };
  }
  continueStmt() {
    const loc = this.current().loc;
    this.expect("CONTINUE");
    return { kind: "ContinueStmt", loc };
  }
  deferStmt() {
    const loc = this.current().loc;
    this.expect("DEFER");
    const body = this.statement();
    return { kind: "DeferStmt", body, loc };
  }
  tryStmt() {
    const loc = this.current().loc;
    this.expect("TRY");
    this.expectNewline();
    const body = this.parseBlock();
    let catchClause;
    if (this.match("CATCH")) {
      const name = this.expectIdentifier();
      this.expectNewline();
      const catchBody = this.parseBlock();
      catchClause = { name, body: catchBody };
    }
    return { kind: "TryStmt", body, catch: catchClause, loc };
  }
  throwStmt() {
    const loc = this.current().loc;
    this.expect("THROW");
    const value = this.expression();
    return { kind: "ThrowStmt", value, loc };
  }
  withStmt() {
    const loc = this.current().loc;
    this.expect("WITH");
    const contexts = [];
    do {
      if (contexts.length > 0)
        this.skipBracketedWhitespace();
      if (this.match("LET")) {
        const name = this.expectIdentifier();
        const nameLoc = this.previous().loc;
        this.expect("ASSIGN");
        this.skipBracketedWhitespace();
        const expr = this.parseContextExpr();
        contexts.push({ expr, name, nameLoc });
      } else {
        const expr = this.parseContextExpr();
        contexts.push({ expr });
      }
    } while (this.match("COMMA"));
    this.expectNewline();
    const body = this.parseBlock();
    return { kind: "WithStmt", contexts, body, loc };
  }
  parseContextExpr() {
    let expr = this.parsePrimaryExpr();
    while (true) {
      if (this.check("LPAREN")) {
        this.advance();
        expr = this.finishCallExpr(expr);
      } else if (this.check("DOT")) {
        this.advance();
        const prop = this.expectIdentifier();
        expr = { kind: "MemberExpr", object: expr, property: prop, optional: false, loc: expr.loc };
      } else if (this.check("OPTIONAL")) {
        this.advance();
        const prop = this.expectIdentifier();
        expr = { kind: "MemberExpr", object: expr, property: prop, optional: true, loc: expr.loc };
      } else {
        break;
      }
    }
    return expr;
  }
  parsePrimaryExpr() {
    const token = this.peek();
    if (token.type === "IDENTIFIER") {
      this.advance();
      return { kind: "Identifier", name: token.value, loc: token.loc };
    }
    if (token.type === "STRING") {
      this.advance();
      return { kind: "Literal", value: token.value, loc: token.loc };
    }
    if (token.type === "NUMBER") {
      this.advance();
      return { kind: "Literal", value: token.value, loc: token.loc };
    }
    const err = ParserErrors.unexpectedTokenInContext(token.type);
    throw new ParseError(err.message, token, err.hint);
  }
  finishCallExpr(callee) {
    const loc = callee.loc;
    const args = [];
    while (true) {
      this.skipBracketedWhitespace();
      if (this.check("RPAREN"))
        break;
      if (this.check("IDENTIFIER") && this.peekNext().type === "COLON") {
        const name = this.expectIdentifier();
        this.expect("COLON");
        const value = this.expression();
        args.push({ name, value });
      } else {
        args.push(this.expression());
      }
      this.skipBracketedWhitespace();
      if (!this.check("RPAREN")) {
        this.expect("COMMA");
      }
    }
    this.expect("RPAREN");
    return { kind: "CallExpr", callee, args, loc };
  }
  exprOrAssignStmt() {
    const loc = this.current().loc;
    const expr = this.expression();
    if (this.check("ASSIGN") || this.check("PLUS_ASSIGN") || this.check("MINUS_ASSIGN") || this.check("STAR_ASSIGN") || this.check("SLASH_ASSIGN") || this.check("PERCENT_ASSIGN")) {
      const op = this.advance().raw;
      const value = this.expression();
      return { kind: "AssignStmt", target: expr, op, value, loc };
    }
    return { kind: "ExprStmt", expr, loc };
  }
  parseBlock() {
    const loc = this.current().loc;
    const statements = [];
    this.expect("INDENT");
    this.skipNewlines();
    while (!this.check("DEDENT") && !this.isAtEnd()) {
      statements.push(this.statement());
      this.skipNewlines();
    }
    this.expect("DEDENT");
    return { kind: "Block", statements, loc };
  }
  expression(precedence = 0 /* NONE */) {
    const token = this.advance();
    const prefixParser = this.prefixParsers.get(token.type);
    if (!prefixParser) {
      const err = ParserErrors.unexpectedToken(token.type);
      throw new ParseError(err.message, token, err.hint);
    }
    let left = prefixParser();
    while (precedence < this.currentPrecedence() || this.tryLineContinuation(precedence)) {
      const infixParser = this.infixParsers.get(this.peek().type);
      if (!infixParser)
        break;
      this.advance();
      left = infixParser(left);
    }
    return left;
  }
  static LINE_CONTINUATION_OPS = new Set([
    "PIPE",
    "PLUS",
    "MINUS",
    "STAR",
    "SLASH",
    "PERCENT",
    "CARET",
    "AND",
    "OR",
    "EQ",
    "NEQ",
    "LT",
    "GT",
    "LTE",
    "GTE",
    "NULLISH",
    "DOTDOT"
  ]);
  tryLineContinuation(precedence) {
    if (!this.check("NEWLINE"))
      return false;
    const savedPos = this.pos;
    while (this.match("NEWLINE")) {}
    if (this.check("INDENT") || this.check("DEDENT")) {
      this.pos = savedPos;
      return false;
    }
    const nextToken = this.peek().type;
    if (!Parser.LINE_CONTINUATION_OPS.has(nextToken)) {
      this.pos = savedPos;
      return false;
    }
    const nextPrec = this.precedences.get(nextToken) ?? 0 /* NONE */;
    const canContinue = nextPrec > precedence;
    if (!canContinue) {
      this.pos = savedPos;
    }
    return canContinue;
  }
  currentPrecedence() {
    return this.precedences.get(this.peek().type) ?? 0 /* NONE */;
  }
  literal() {
    const token = this.previous();
    if (token.type === "STRING" && typeof token.value === "string") {
      const str = token.value;
      if (str.includes("{") && str.includes("}")) {
        return this.parseTemplateString(str, token.loc);
      }
    }
    return {
      kind: "Literal",
      value: token.value,
      loc: token.loc
    };
  }
  parseTemplateString(str, loc) {
    const parts = [];
    let currentText = "";
    let i = 0;
    while (i < str.length) {
      if (str[i] === "{") {
        if (currentText) {
          parts.push(currentText);
          currentText = "";
        }
        let depth = 1;
        let exprStart = i + 1;
        i++;
        while (i < str.length && depth > 0) {
          if (str[i] === "{")
            depth++;
          else if (str[i] === "}")
            depth--;
          i++;
        }
        const exprStr = str.slice(exprStart, i - 1);
        const exprParts = exprStr.trim();
        const exprLoc = {
          line: loc.line,
          column: loc.column + 1 + exprStart,
          offset: loc.offset + 1 + exprStart
        };
        if (/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(exprParts)) {
          parts.push({
            kind: "TemplateExpr",
            expr: { kind: "Identifier", name: exprParts, loc: exprLoc },
            loc: exprLoc
          });
        } else {
          try {
            const parser = new Parser(exprParts);
            const program = parser.parse();
            if (program.body.length === 1 && program.body[0]?.kind === "ExprStmt") {
              const expr = program.body[0].expr;
              this.adjustExprLocations(expr, exprLoc);
              parts.push({
                kind: "TemplateExpr",
                expr,
                loc: exprLoc
              });
            }
          } catch {
            parts.push("{" + exprParts + "}");
          }
        }
      } else {
        currentText += str[i];
        i++;
      }
    }
    if (currentText) {
      parts.push(currentText);
    }
    return { kind: "TemplateLiteral", parts, loc };
  }
  adjustExprLocations(expr, baseLoc) {
    expr.loc = {
      line: baseLoc.line,
      column: baseLoc.column + expr.loc.column - 1,
      offset: baseLoc.offset + expr.loc.offset
    };
    if (expr.kind === "MemberExpr") {
      this.adjustExprLocations(expr.object, baseLoc);
    } else if (expr.kind === "CallExpr") {
      this.adjustExprLocations(expr.callee, baseLoc);
      for (const arg of expr.args) {
        if ("kind" in arg)
          this.adjustExprLocations(arg, baseLoc);
      }
    } else if (expr.kind === "BinaryExpr") {
      this.adjustExprLocations(expr.left, baseLoc);
      this.adjustExprLocations(expr.right, baseLoc);
    } else if (expr.kind === "IndexExpr") {
      this.adjustExprLocations(expr.object, baseLoc);
      this.adjustExprLocations(expr.index, baseLoc);
    }
  }
  identifier() {
    const token = this.previous();
    return {
      kind: "Identifier",
      name: token.value,
      loc: token.loc
    };
  }
  groupOrLambda() {
    const loc = this.previous().loc;
    if (this.check("RPAREN")) {
      this.advance();
      if (this.match("ARROW")) {
        return this.parseLambdaBody([], loc);
      }
      const err = ParserErrors.emptyParentheses();
      throw new ParseError(err.message, this.current(), err.hint);
    }
    const first = this.expression();
    if (this.check("COMMA") || first.kind === "Identifier" && this.check("COLON")) {
      return this.parseLambdaFromFirst(first, loc);
    }
    this.expect("RPAREN");
    if (this.match("ARROW")) {
      if (first.kind !== "Identifier") {
        const err = ParserErrors.lambdaParamMustBeIdentifier();
        throw new ParseError(err.message, this.current(), err.hint);
      }
      const params = [{
        kind: "Parameter",
        name: first.name,
        optional: false,
        rest: false,
        loc: first.loc
      }];
      return this.parseLambdaBody(params, loc);
    }
    return first;
  }
  parseLambdaFromFirst(first, loc) {
    const params = [];
    if (first.kind !== "Identifier") {
      const err = ParserErrors.lambdaParamMustBeIdentifier();
      throw new ParseError(err.message, this.current(), err.hint);
    }
    let type;
    if (this.match("COLON")) {
      type = this.parseType();
    }
    params.push({ kind: "Parameter", name: first.name, type, optional: false, rest: false, loc: first.loc });
    while (this.match("COMMA")) {
      const paramLoc = this.current().loc;
      const name = this.expectIdentifier();
      let paramType;
      if (this.match("COLON")) {
        paramType = this.parseType();
      }
      params.push({ kind: "Parameter", name, type: paramType, optional: false, rest: false, loc: paramLoc });
    }
    this.expect("RPAREN");
    this.expect("ARROW");
    return this.parseLambdaBody(params, loc);
  }
  parseLambdaBody(params, loc) {
    const body = this.expression();
    return { kind: "LambdaExpr", params, body, loc };
  }
  listExpr() {
    const loc = this.previous().loc;
    const elements = [];
    this.skipBracketedWhitespace();
    while (!this.check("RBRACKET")) {
      if (this.match("SPREAD")) {
        const expr = this.expression();
        elements.push({ kind: "SpreadElement", expr, loc: expr.loc });
      } else {
        elements.push(this.expression());
      }
      this.skipBracketedWhitespace();
      if (!this.check("RBRACKET")) {
        this.expect("COMMA");
        this.skipBracketedWhitespace();
      }
    }
    this.expect("RBRACKET");
    return { kind: "ListExpr", elements, loc };
  }
  setExpr() {
    const loc = this.previous().loc;
    const elements = [];
    this.skipBracketedWhitespace();
    if (this.check("GT")) {
      this.advance();
      return { kind: "SetExpr", elements, loc };
    }
    while (!this.check("GT")) {
      elements.push(this.expression(7 /* COMPARISON */));
      this.skipBracketedWhitespace();
      if (!this.check("GT"))
        this.expect("COMMA");
      this.skipBracketedWhitespace();
    }
    this.expect("GT");
    return { kind: "SetExpr", elements, loc };
  }
  mapExpr() {
    const loc = this.previous().loc;
    const entries = [];
    this.skipBracketedWhitespace();
    while (!this.check("RBRACE")) {
      const entryLoc = this.current().loc;
      if (this.match("SPREAD")) {
        const expr = this.expression();
        entries.push({ kind: "MapEntry", key: expr, value: expr, spread: true, loc: entryLoc });
      } else if (this.peekNext().type === "COLON" && (this.check("IDENTIFIER") || KEYWORD_TOKEN_TYPES.has(this.peek().type))) {
        const t = this.advance();
        const key = { kind: "Identifier", name: t.raw, loc: t.loc };
        this.expect("COLON");
        const value = this.expression();
        entries.push({ kind: "MapEntry", key, value, loc: entryLoc });
      } else {
        const key = this.expression();
        this.expect("COLON");
        const value = this.expression();
        entries.push({ kind: "MapEntry", key, value, loc: entryLoc });
      }
      this.skipBracketedWhitespace();
      if (!this.check("RBRACE")) {
        this.expect("COMMA");
        this.skipBracketedWhitespace();
      }
    }
    this.expect("RBRACE");
    return { kind: "MapExpr", entries, loc };
  }
  unary() {
    const token = this.previous();
    const operand = this.expression(12 /* UNARY */);
    return { kind: "UnaryExpr", op: token.raw, operand, loc: token.loc };
  }
  binary(left) {
    const token = this.previous();
    const right = this.expression(this.precedences.get(token.type) ?? 0 /* NONE */);
    return { kind: "BinaryExpr", op: token.raw, left, right, loc: token.loc };
  }
  binaryRight(left) {
    const token = this.previous();
    const right = this.expression((this.precedences.get(token.type) ?? 0 /* NONE */) - 1);
    return { kind: "BinaryExpr", op: token.raw, left, right, loc: token.loc };
  }
  callExpr(callee) {
    const loc = this.previous().loc;
    const args = [];
    while (!this.check("RPAREN")) {
      if (this.check("IDENTIFIER") && this.peekNext().type === "COLON") {
        const name = this.expectIdentifier();
        this.expect("COLON");
        const value = this.expression();
        args.push({ name, value });
      } else {
        args.push(this.expression());
      }
      if (!this.check("RPAREN")) {
        this.expect("COMMA");
      }
    }
    this.expect("RPAREN");
    return { kind: "CallExpr", callee, args, loc };
  }
  indexExpr(object, optional) {
    const loc = this.previous().loc;
    if (this.check("COLON")) {
      return this.sliceExpr(object, undefined, loc, optional);
    }
    const index = this.expression();
    if (this.check("COLON")) {
      return this.sliceExpr(object, index, loc, optional);
    }
    const typeArgs = [];
    while (this.match("COMMA")) {
      typeArgs.push(this.expression());
    }
    this.expect("RBRACKET");
    if (typeArgs.length > 0) {
      return { kind: "IndexExpr", object, index, optional, typeArgs, loc };
    }
    return { kind: "IndexExpr", object, index, optional, loc };
  }
  sliceExpr(object, start, loc, optional) {
    this.expect("COLON");
    let end;
    let step;
    if (!this.check("COLON") && !this.check("RBRACKET")) {
      end = this.expression();
    }
    if (this.match("COLON")) {
      if (!this.check("RBRACKET")) {
        step = this.expression();
      }
    }
    this.expect("RBRACKET");
    const dummyIndex = { kind: "Literal", value: 0, loc };
    return {
      kind: "IndexExpr",
      object,
      index: dummyIndex,
      optional,
      slice: { start, end, step },
      loc
    };
  }
  memberExpr(object, optional) {
    const loc = this.previous().loc;
    const property = this.expectIdentifier();
    return { kind: "MemberExpr", object, property, optional, loc };
  }
  pipeExpr(left) {
    const loc = this.previous().loc;
    const right = this.expression(2 /* PIPE */);
    return { kind: "PipeExpr", left, right, loc };
  }
  rangeExpr(start) {
    const loc = this.previous().loc;
    const end = this.expression(8 /* RANGE */);
    return { kind: "RangeExpr", start, end, inclusive: false, loc };
  }
  isExpr(left) {
    const loc = this.previous().loc;
    const right = this.parseType();
    return {
      kind: "BinaryExpr",
      op: "is",
      left,
      right: { kind: "Identifier", name: right.name, loc },
      loc
    };
  }
  asExpr(expr) {
    const loc = this.previous().loc;
    const type = this.parseType();
    return { kind: "TypeAssertion", expr, type, loc };
  }
  nullAssertion(expr) {
    const loc = this.previous().loc;
    return { kind: "NullAssertion", expr, loc };
  }
  ifExpr() {
    const loc = this.previous().loc;
    const condition = this.expression();
    this.expect("THEN");
    const thenExpr = this.expression();
    this.expect("ELSE");
    const elseExpr = this.expression();
    return { kind: "IfExpr", condition, then: thenExpr, else: elseExpr, loc };
  }
  matchExpr() {
    const loc = this.previous().loc;
    const value = this.expression();
    this.expectNewline();
    this.expect("INDENT");
    this.skipNewlines();
    const arms = [];
    while (!this.check("DEDENT") && !this.isAtEnd()) {
      arms.push(this.parseMatchArm());
      this.skipNewlines();
    }
    this.expect("DEDENT");
    return { kind: "MatchExpr", value, arms, loc };
  }
  spawnExpr() {
    const loc = this.previous().loc;
    const expr = this.expression(12 /* UNARY */);
    return { kind: "SpawnExpr", expr, loc };
  }
  parsePattern() {
    const token = this.peek();
    if (token.type === "LBRACE") {
      return this.objectPattern();
    }
    if (token.type === "LBRACKET") {
      return this.arrayPattern();
    }
    if (token.type === "SPREAD") {
      this.advance();
      const name = this.expectIdentifier();
      return { kind: "RestPattern", name, loc: token.loc };
    }
    if (token.type === "NUMBER") {
      this.advance();
      const value = token.value;
      if (this.match("DOTDOT")) {
        const endToken = this.expect("NUMBER");
        return { kind: "RangePattern", start: value, end: endToken.value, loc: token.loc };
      }
      return { kind: "LiteralPattern", value, loc: token.loc };
    }
    if (token.type === "STRING") {
      this.advance();
      return { kind: "LiteralPattern", value: token.value, loc: token.loc };
    }
    if (token.type === "TRUE" || token.type === "FALSE") {
      this.advance();
      return { kind: "LiteralPattern", value: token.value, loc: token.loc };
    }
    if (token.type === "NULL") {
      this.advance();
      return { kind: "LiteralPattern", value: null, loc: token.loc };
    }
    if (token.type === "IDENTIFIER") {
      this.advance();
      const name = token.value;
      if (name === "_") {
        return { kind: "WildcardPattern", loc: token.loc };
      }
      if (this.check("AS")) {
        this.advance();
        const binding = this.expectIdentifier();
        return { kind: "TypePattern", type: { kind: "NamedType", name, loc: token.loc }, binding, loc: token.loc };
      }
      return { kind: "IdentifierPattern", name, loc: token.loc };
    }
    const err = ParserErrors.expectedPattern(token.type);
    throw new ParseError(err.message, token, err.hint);
  }
  objectPattern() {
    const loc = this.current().loc;
    this.expect("LBRACE");
    const properties = [];
    while (!this.check("RBRACE")) {
      const key = this.expectIdentifier();
      let pattern = { kind: "IdentifierPattern", name: key, loc: this.current().loc };
      if (this.match("COLON")) {
        pattern = this.parsePattern();
      }
      properties.push({ key, pattern });
      if (!this.check("RBRACE")) {
        this.expect("COMMA");
      }
    }
    this.expect("RBRACE");
    return { kind: "ObjectPattern", properties, loc };
  }
  arrayPattern() {
    const loc = this.current().loc;
    this.expect("LBRACKET");
    const elements = [];
    while (!this.check("RBRACKET")) {
      elements.push(this.parsePattern());
      if (!this.check("RBRACKET")) {
        this.expect("COMMA");
      }
    }
    this.expect("RBRACKET");
    return { kind: "ArrayPattern", elements, loc };
  }
  parseType() {
    let type = this.parsePrimaryType();
    if (this.check("OR")) {
      const types = [type];
      while (this.match("OR")) {
        types.push(this.parsePrimaryType());
      }
      type = { kind: "UnionType", types, loc: type.loc };
    }
    if (this.match("QUESTION")) {
      type = { kind: "OptionalType", inner: type, loc: type.loc };
    }
    return type;
  }
  parsePrimaryType() {
    const token = this.peek();
    if (token.type === "FN") {
      return this.parseFunctionType();
    }
    if (token.type === "IDENTIFIER") {
      this.advance();
      const name = token.value;
      if (this.check("IS")) {
        this.advance();
        const targetType = this.parsePrimaryType();
        return { kind: "TypePredicateExpr", paramName: name, targetType, loc: token.loc };
      }
      if (this.check("LBRACKET")) {
        this.advance();
        const args = [];
        while (!this.check("RBRACKET")) {
          args.push(this.parseType());
          if (!this.check("RBRACKET")) {
            this.expect("COMMA");
          }
        }
        this.expect("RBRACKET");
        return { kind: "GenericType", name, args, loc: token.loc };
      }
      return { kind: "NamedType", name, loc: token.loc };
    }
    if (token.type === "STRING") {
      this.advance();
      return { kind: "NamedType", name: `"${token.value}"`, loc: token.loc };
    }
    const err = ParserErrors.expectedType(token.type);
    throw new ParseError(err.message, token, err.hint);
  }
  parseFunctionType() {
    const loc = this.current().loc;
    this.expect("FN");
    this.expect("LPAREN");
    const params = [];
    while (!this.check("RPAREN")) {
      params.push(this.parseType());
      if (!this.check("RPAREN")) {
        this.expect("COMMA");
      }
    }
    this.expect("RPAREN");
    this.expect("COLON");
    const returnType = this.parseType();
    return { kind: "FunctionType", params, returnType, loc };
  }
  containsYield(block) {
    for (const stmt of block.statements) {
      if (stmt.kind === "YieldStmt")
        return true;
      if (stmt.kind === "IfStmt") {
        if (stmt.then.kind === "Block" && this.containsYield(stmt.then))
          return true;
        for (const elif of stmt.elseIfs) {
          if (this.containsYield(elif.body))
            return true;
        }
        if (stmt.else && this.containsYield(stmt.else))
          return true;
      }
      if (stmt.kind === "ForStmt" && this.containsYield(stmt.body))
        return true;
      if (stmt.kind === "TryStmt") {
        if (this.containsYield(stmt.body))
          return true;
        if (stmt.catch && this.containsYield(stmt.catch.body))
          return true;
      }
    }
    return false;
  }
  peek() {
    return this.tokens[this.pos] ?? this.tokens[this.tokens.length - 1];
  }
  peekNext() {
    return this.tokens[this.pos + 1] ?? this.tokens[this.tokens.length - 1];
  }
  previous() {
    return this.tokens[this.pos - 1];
  }
  current() {
    return this.tokens[this.pos];
  }
  advance() {
    if (!this.isAtEnd())
      this.pos++;
    return this.previous();
  }
  isAtEnd() {
    return this.peek().type === "EOF";
  }
  check(type) {
    return this.peek().type === type;
  }
  match(type) {
    if (this.check(type)) {
      this.advance();
      return true;
    }
    return false;
  }
  expect(type) {
    if (this.check(type)) {
      return this.advance();
    }
    const err = ParserErrors.expectedToken(type, this.peek().type);
    throw new ParseError(err.message, this.peek(), err.hint);
  }
  expectIdentifier() {
    const token = this.expect("IDENTIFIER");
    return token.value;
  }
  expectName() {
    const token = this.current();
    if (token.type === "IDENTIFIER") {
      this.advance();
      return token.value;
    }
    const err = ParserErrors.expectedName(token.type);
    throw new ParseError(err.message, token, err.hint);
  }
  expectString() {
    const token = this.expect("STRING");
    return token.value;
  }
  expectNewline() {
    if (!this.check("NEWLINE") && !this.check("EOF")) {
      const err = ParserErrors.expectedNewline(this.peek().type);
      throw new ParseError(err.message, this.peek(), err.hint);
    }
    this.match("NEWLINE");
  }
  skipNewlines() {
    while (this.match("NEWLINE")) {}
  }
  skipBracketedWhitespace() {
    while (this.match("NEWLINE") || this.match("INDENT") || this.match("DEDENT")) {}
  }
}
// src/codegen/types.ts
var defaultOptions = {
  indent: "  ",
  sourceMap: false,
  runtime: "bun",
  module: "cjs",
  emitRuntimeImport: true
};
function getTypeName(node) {
  const t = node.resolvedType;
  if (t?.kind === "object")
    return t.name;
  if (t?.kind === "ref")
    return t.name;
  return;
}
function isTypeConstructor(node) {
  const t = node.resolvedType;
  if (!t)
    return false;
  if (t.kind === "object" && !!t.name)
    return true;
  if (t.kind === "function") {
    const fnType = t;
    const retType = fnType.returnType;
    if (retType.kind === "object" && !!retType.name)
      return true;
    if (retType.kind === "generic")
      return true;
  }
  return false;
}
function getParamOrder(node) {
  const t = node.resolvedType;
  if (t?.kind === "function") {
    return t.params.map((p) => p.name);
  }
  if (t?.kind === "object") {
    return t.properties.map((p) => p.name);
  }
  return;
}
function createCtx(options = {}) {
  return {
    out: [],
    indent: 0,
    typeFields: new Map,
    options: { ...defaultOptions, ...options },
    scopeStack: [],
    tempCounter: 0
  };
}
function createOpts(overrides = {}) {
  return {
    implicitReturn: false,
    classFields: null,
    isGenerator: false,
    ...overrides
  };
}
function emit(ctx, line) {
  ctx.out.push(ctx.options.indent.repeat(ctx.indent) + line);
}
function pushIndent(ctx) {
  ctx.indent++;
}
function popIndent(ctx) {
  ctx.indent--;
}
function tempVar(ctx, prefix = "_t") {
  return `${prefix}${ctx.tempCounter++}`;
}
function pushScope(ctx) {
  ctx.scopeStack.push({ defers: [] });
}
function popScope(ctx) {
  return ctx.scopeStack.pop()?.defers || [];
}
function addDefer(ctx, stmt) {
  const scope = ctx.scopeStack[ctx.scopeStack.length - 1];
  if (scope) {
    scope.defers.push(stmt);
  }
}
function getOutput(ctx) {
  return ctx.out.join(`
`);
}
function resetCtx(ctx) {
  ctx.out = [];
  ctx.indent = 0;
  ctx.scopeStack = [];
  ctx.tempCounter = 0;
  ctx.typeFields = new Map;
}

// src/types/types.ts
var Types = {
  number: { kind: "number" },
  string: { kind: "string" },
  bool: { kind: "bool" },
  null: { kind: "null" },
  bytes: { kind: "bytes" },
  never: { kind: "never" },
  unknown: { kind: "unknown" },
  void: { kind: "void" },
  list(elementType) {
    return { kind: "list", elementType };
  },
  map(keyType, valueType) {
    return { kind: "map", keyType, valueType };
  },
  set(elementType) {
    return { kind: "set", elementType };
  },
  tuple(...elements) {
    return { kind: "tuple", elements };
  },
  fn(params, returnType, context = []) {
    return { kind: "function", params, returnType, isGenerator: false, context };
  },
  generator(params, yieldType, context = []) {
    return {
      kind: "function",
      params,
      returnType: Types.stream(yieldType),
      isGenerator: true,
      context
    };
  },
  object(props, methods = [], name) {
    return { kind: "object", name, properties: props, methods };
  },
  union(...types) {
    const flattened = [];
    for (const t of types) {
      if (t.kind === "union") {
        flattened.push(...t.types);
      } else {
        flattened.push(t);
      }
    }
    return { kind: "union", types: flattened };
  },
  intersection(...types) {
    return { kind: "intersection", types };
  },
  optional(inner) {
    return { kind: "optional", inner };
  },
  literal(value) {
    return { kind: "literal", value };
  },
  typevar(name, constraint) {
    return { kind: "typevar", name, constraint };
  },
  generic(base, args) {
    return { kind: "generic", base, args };
  },
  ref(name, args) {
    return { kind: "ref", name, args };
  },
  channel(elementType) {
    return { kind: "channel", elementType };
  },
  promise(resolveType) {
    return { kind: "promise", resolveType };
  },
  stream(elementType) {
    return { kind: "stream", elementType };
  },
  result(okType, errType) {
    return { kind: "result", okType, errType };
  },
  param(name, type, optional = false, rest = false) {
    return { name, type, optional, rest };
  },
  prop(name, type, optional = false) {
    return { name, type, optional, computed: false };
  }
};
function isNullable(type) {
  if (type.kind === "null")
    return true;
  if (type.kind === "optional")
    return true;
  if (type.kind === "union") {
    return type.types.some((t) => t.kind === "null");
  }
  return false;
}
function nonNull(type) {
  if (type.kind === "optional")
    return type.inner;
  if (type.kind === "union") {
    const nonNullTypes = type.types.filter((t) => t.kind !== "null");
    if (nonNullTypes.length === 1)
      return nonNullTypes[0];
    return Types.union(...nonNullTypes);
  }
  return type;
}
function typeToString(type) {
  switch (type.kind) {
    case "number":
    case "string":
    case "bool":
    case "null":
    case "bytes":
    case "never":
    case "unknown":
    case "void":
      return type.kind;
    case "list":
      return `list[${typeToString(type.elementType)}]`;
    case "map":
      return `map[${typeToString(type.keyType)}, ${typeToString(type.valueType)}]`;
    case "set":
      return `set[${typeToString(type.elementType)}]`;
    case "tuple":
      return `(${type.elements.map(typeToString).join(", ")})`;
    case "function": {
      const params = type.params.map((p) => {
        let s = p.name;
        if (p.optional)
          s += "?";
        s += ": " + typeToString(p.type);
        if (p.rest)
          s = "..." + s;
        return s;
      }).join(", ");
      const ret = typeToString(type.returnType);
      const ctx = type.context.length > 0 ? ` using (${type.context.map((c) => c.name ? `${c.name}: ${typeToString(c.type)}` : typeToString(c.type)).join(", ")})` : "";
      return `fn(${params}): ${ret}${ctx}`;
    }
    case "object":
      return type.name ?? "{ ... }";
    case "interface":
      return type.name;
    case "union":
      return type.types.map(typeToString).join(" | ");
    case "intersection":
      return type.types.map(typeToString).join(" & ");
    case "optional":
      return `${typeToString(type.inner)}?`;
    case "literal":
      return typeof type.value === "string" ? `"${type.value}"` : String(type.value);
    case "typevar":
      return type.name;
    case "generic":
      return `${typeToString(type.base)}[${type.args.map(typeToString).join(", ")}]`;
    case "ref":
      return type.args ? `${type.name}[${type.args.map(typeToString).join(", ")}]` : type.name;
    case "agent":
      return `agent ${type.name}`;
    case "channel":
      return `Channel[${typeToString(type.elementType)}]`;
    case "promise":
      return `Promise[${typeToString(type.resolveType)}]`;
    case "stream":
      return `Stream[${typeToString(type.elementType)}]`;
    case "result":
      return `Result[${typeToString(type.okType)}, ${typeToString(type.errType)}]`;
    default:
      return "unknown";
  }
}

// src/types/primitives.ts
var PRIMITIVE_TYPE_MAP = {
  number: Types.number,
  string: Types.string,
  bool: Types.bool,
  null: Types.null,
  bytes: Types.bytes,
  unknown: Types.unknown,
  never: Types.never,
  void: Types.void
};
var GENERIC_TYPE_CONSTRUCTORS = {
  list: (args) => args[0] ? Types.list(args[0]) : undefined,
  map: (args) => args[0] && args[1] ? Types.map(args[0], args[1]) : undefined,
  set: (args) => args[0] ? Types.set(args[0]) : undefined,
  Promise: (args) => args[0] ? Types.promise(args[0]) : undefined,
  Stream: (args) => args[0] ? Types.stream(args[0]) : undefined,
  Channel: (args) => args[0] ? Types.channel(args[0]) : undefined
};
function constructGenericType(name, args) {
  const constructor = GENERIC_TYPE_CONSTRUCTORS[name];
  if (constructor) {
    return constructor(args);
  }
  return;
}

// src/types/type-utils.ts
function astTypeToType(astType) {
  switch (astType.kind) {
    case "NamedType": {
      const primitiveType = PRIMITIVE_TYPE_MAP[astType.name];
      if (primitiveType) {
        return primitiveType;
      }
      if (astType.name === "list")
        return Types.list(Types.unknown);
      if (astType.name === "map")
        return Types.map(Types.unknown, Types.unknown);
      if (astType.name === "set")
        return Types.set(Types.unknown);
      return Types.ref(astType.name);
    }
    case "GenericType": {
      const args = astType.args.map((a) => astTypeToType(a));
      const constructed = constructGenericType(astType.name, args);
      if (constructed) {
        return constructed;
      }
      return Types.generic(Types.ref(astType.name), args);
    }
    case "FunctionType":
      return Types.fn(astType.params.map((p, i) => Types.param(`arg${i}`, astTypeToType(p))), astTypeToType(astType.returnType));
    case "UnionType":
      return Types.union(...astType.types.map((t) => astTypeToType(t)));
    case "OptionalType":
      return Types.optional(astTypeToType(astType.inner));
    case "ListType":
      return Types.list(astTypeToType(astType.elementType));
    case "MapType":
      return Types.map(astTypeToType(astType.keyType), astTypeToType(astType.valueType));
    case "TypePredicateExpr":
      return Types.bool;
    default:
      return Types.unknown;
  }
}
function resolveTypeName(name, env) {
  const primitiveType = PRIMITIVE_TYPE_MAP[name];
  if (primitiveType) {
    return primitiveType;
  }
  const resolved = env.lookup(name);
  if (resolved)
    return resolved.type;
  return Types.ref(name);
}
function fnDeclToType(decl) {
  const params = decl.params.map((p) => ({
    name: p.name,
    type: p.type ? astTypeToType(p.type) : Types.unknown,
    optional: p.optional,
    rest: p.rest
  }));
  const returnType = decl.returnType ? astTypeToType(decl.returnType) : Types.unknown;
  const context = decl.using?.bindings.map((c) => ({
    name: c.name,
    type: astTypeToType(c.type)
  })) ?? [];
  const typeParams = decl.typeParams?.map((p) => ({
    name: p.name,
    constraint: p.constraint ? astTypeToType(p.constraint) : undefined
  }));
  return {
    kind: "function",
    typeParams,
    params,
    returnType,
    isGenerator: decl.isGenerator,
    context
  };
}
function methodToFunctionType(method) {
  const params = method.params.map((p) => ({
    name: p.name,
    type: p.type ? astTypeToType(p.type) : Types.unknown,
    optional: p.optional,
    rest: p.rest
  }));
  const returnType = method.returnType ? astTypeToType(method.returnType) : Types.unknown;
  const context = method.using?.bindings.map((c) => ({
    name: c.name,
    type: astTypeToType(c.type)
  })) ?? [];
  const typeParams = method.typeParams?.map((p) => ({
    name: p.name,
    constraint: p.constraint ? astTypeToType(p.constraint) : undefined
  }));
  return {
    kind: "function",
    typeParams,
    params,
    returnType,
    isGenerator: false,
    context
  };
}
function isAssignable(source, target, env) {
  if (target.kind === "unknown")
    return true;
  if (source.kind === "unknown")
    return false;
  if (source.kind === "never")
    return true;
  if (target.kind === "never")
    return false;
  const resolvedSource = source.kind === "ref" ? env.resolveType(source) : source;
  const resolvedTarget = target.kind === "ref" ? env.resolveType(target) : target;
  if (resolvedSource.kind === resolvedTarget.kind) {
    switch (resolvedSource.kind) {
      case "number":
      case "string":
      case "bool":
      case "null":
      case "bytes":
      case "void":
      case "never":
        return true;
      case "ref":
        return resolvedSource.name === resolvedTarget.name;
      case "list":
        if (resolvedTarget.elementType.kind === "unknown")
          return true;
        return isAssignable(resolvedSource.elementType, resolvedTarget.elementType, env) && isAssignable(resolvedTarget.elementType, resolvedSource.elementType, env);
      case "map":
        if (resolvedTarget.keyType.kind === "unknown" && resolvedTarget.valueType.kind === "unknown")
          return true;
        return isAssignable(resolvedSource.keyType, resolvedTarget.keyType, env) && isAssignable(resolvedTarget.keyType, resolvedSource.keyType, env) && isAssignable(resolvedSource.valueType, resolvedTarget.valueType, env) && isAssignable(resolvedTarget.valueType, resolvedSource.valueType, env);
      case "channel":
        if (resolvedTarget.elementType.kind === "unknown")
          return true;
        return isAssignable(resolvedSource.elementType, resolvedTarget.elementType, env) && isAssignable(resolvedTarget.elementType, resolvedSource.elementType, env);
      case "promise":
        if (resolvedTarget.resolveType.kind === "unknown")
          return true;
        return isAssignable(resolvedSource.resolveType, resolvedTarget.resolveType, env);
      case "set":
        if (resolvedTarget.elementType.kind === "unknown")
          return true;
        return isAssignable(resolvedSource.elementType, resolvedTarget.elementType, env) && isAssignable(resolvedTarget.elementType, resolvedSource.elementType, env);
      case "stream":
        if (resolvedTarget.elementType.kind === "unknown")
          return true;
        return isAssignable(resolvedSource.elementType, resolvedTarget.elementType, env);
      case "tuple":
        return isTupleAssignable(resolvedSource, resolvedTarget, env);
      case "object":
        return isObjectAssignable(resolvedSource, resolvedTarget, env);
      case "interface": {
        const src = resolvedSource;
        const tgt = resolvedTarget;
        if (src.name === tgt.name)
          return true;
        for (const tgtMethod of tgt.methods) {
          const srcMethod = src.methods.find((m) => m.name === tgtMethod.name);
          if (!srcMethod)
            return false;
          if (!isFunctionAssignable(srcMethod.type, tgtMethod.type, env))
            return false;
        }
        return true;
      }
      case "function":
        return isFunctionAssignable(resolvedSource, resolvedTarget, env);
      case "intersection":
        return isIntersectionAssignable(resolvedSource, resolvedTarget, env);
      case "generic":
        return isGenericAssignable(resolvedSource, resolvedTarget, env);
      case "typevar":
        return resolvedSource.name === resolvedTarget.name;
      default:
        return true;
    }
  }
  if (resolvedSource.kind === "typevar") {
    return resolvedTarget.kind === "unknown" || resolvedTarget.kind === "typevar" && resolvedSource.name === resolvedTarget.name;
  }
  if (resolvedTarget.kind === "typevar") {
    return true;
  }
  if (resolvedSource.kind === "null" && resolvedTarget.kind === "optional")
    return true;
  if (resolvedTarget.kind === "optional") {
    if (resolvedSource.kind === "union") {
      const unionTypes = resolvedSource.types;
      const nonNullTypes = unionTypes.filter((t) => t.kind !== "null");
      if (nonNullTypes.length === unionTypes.length - 1) {
        return nonNullTypes.every((t) => isAssignable(t, resolvedTarget.inner, env));
      }
    }
    return isAssignable(resolvedSource, resolvedTarget.inner, env);
  }
  if (resolvedTarget.kind === "union") {
    return resolvedTarget.types.some((t) => isAssignable(resolvedSource, t, env));
  }
  if (resolvedSource.kind === "union") {
    return resolvedSource.types.every((t) => isAssignable(t, resolvedTarget, env));
  }
  if (resolvedSource.kind === "intersection") {
    return resolvedSource.types.some((t) => isAssignable(t, resolvedTarget, env));
  }
  if (resolvedTarget.kind === "intersection") {
    return resolvedTarget.types.every((t) => isAssignable(resolvedSource, t, env));
  }
  if (resolvedTarget.kind === "interface") {
    const concrete = resolvedSource.kind === "ref" ? env.resolveType(resolvedSource) : resolvedSource;
    if (concrete.kind !== "object")
      return false;
    const obj = concrete;
    const iface = resolvedTarget;
    for (const ifaceMethod of iface.methods) {
      const objMethod = obj.methods.find((m) => m.name === ifaceMethod.name);
      if (!objMethod)
        return false;
      if (!isFunctionAssignable(objMethod.type, ifaceMethod.type, env))
        return false;
    }
    return true;
  }
  return false;
}
function isObjectAssignable(source, target, env) {
  if (source.name && target.name) {
    return source.name === target.name;
  }
  if (target.name && !source.name) {
    for (const targetProp of target.properties) {
      if (targetProp.optional)
        continue;
      const sourceProp = source.properties.find((p) => p.name === targetProp.name);
      if (!sourceProp)
        return false;
      if (!isAssignable(sourceProp.type, targetProp.type, env))
        return false;
    }
    return true;
  }
  for (const targetProp of target.properties) {
    if (targetProp.optional)
      continue;
    const sourceProp = source.properties.find((p) => p.name === targetProp.name);
    if (!sourceProp)
      return false;
    if (!isAssignable(sourceProp.type, targetProp.type, env))
      return false;
  }
  for (const targetMethod of target.methods) {
    const sourceMethod = source.methods.find((m) => m.name === targetMethod.name);
    if (!sourceMethod)
      return false;
    if (!isFunctionAssignable(sourceMethod.type, targetMethod.type, env))
      return false;
  }
  return true;
}
function isFunctionAssignable(source, target, env) {
  const sourceRequired = source.params.filter((p) => !p.optional && !p.rest).length;
  const targetRequired = target.params.filter((p) => !p.optional && !p.rest).length;
  if (sourceRequired > targetRequired)
    return false;
  for (let i = 0;i < target.params.length; i++) {
    const targetParam = target.params[i];
    const sourceParam = source.params[i];
    if (!sourceParam) {
      if (!targetParam.optional && !targetParam.rest)
        return false;
      continue;
    }
    if (!isAssignable(targetParam.type, sourceParam.type, env)) {
      return false;
    }
  }
  if (!isAssignable(source.returnType, target.returnType, env))
    return false;
  return true;
}
function isTupleAssignable(source, target, env) {
  if (source.elements.length !== target.elements.length)
    return false;
  for (let i = 0;i < source.elements.length; i++) {
    if (!isAssignable(source.elements[i], target.elements[i], env))
      return false;
  }
  return true;
}
function isIntersectionAssignable(source, target, env) {
  for (const targetType of target.types) {
    const hasMatch = source.types.some((st) => isAssignable(st, targetType, env));
    if (!hasMatch)
      return false;
  }
  return true;
}
function isGenericAssignable(source, target, env) {
  if (!isAssignable(source.base, target.base, env))
    return false;
  const minLen = Math.min(source.args.length, target.args.length);
  for (let i = 0;i < minLen; i++) {
    if (!isAssignable(source.args[i], target.args[i], env))
      return false;
  }
  return true;
}
function isIterable(type) {
  const kind = type.kind;
  if (kind === "list" || kind === "set" || kind === "string" || kind === "map" || kind === "stream" || kind === "channel") {
    return true;
  }
  if (kind === "generic") {
    const genType = type;
    if (genType.base?.kind === "ref") {
      const baseName = genType.base.name.toLowerCase();
      return baseName === "channel" || baseName === "list" || baseName === "set" || baseName === "map" || baseName === "stream";
    }
  }
  return false;
}
function getIterableElementType(type) {
  if (type.kind === "list")
    return type.elementType;
  if (type.kind === "set")
    return type.elementType;
  if (type.kind === "string")
    return Types.string;
  if (type.kind === "map")
    return Types.tuple(type.keyType, type.valueType);
  if (type.kind === "stream")
    return type.elementType;
  if (type.kind === "channel")
    return type.elementType;
  return Types.unknown;
}
function findCommonType(types) {
  if (types.length === 0)
    return Types.unknown;
  if (types.length === 1)
    return types[0];
  const first = types[0];
  if (types.every((t) => t.kind === first.kind)) {
    return first;
  }
  return Types.union(...types);
}
function typeInvolvesPromise(t, env, visited = new Set) {
  if (t.kind === "promise")
    return true;
  if (t.kind === "list")
    return typeInvolvesPromise(t.elementType, env, visited);
  if (t.kind === "map")
    return typeInvolvesPromise(t.valueType, env, visited);
  if (t.kind === "optional")
    return typeInvolvesPromise(t.inner, env, visited);
  if (t.kind === "object") {
    const objType = t;
    if (objType.name && visited.has(objType.name))
      return false;
    if (objType.name)
      visited.add(objType.name);
    for (const prop of objType.properties || []) {
      if (typeInvolvesPromise(prop.type, env, visited))
        return true;
    }
  }
  if (t.kind === "ref") {
    const resolved = env.resolveType(t);
    if (resolved && resolved !== t) {
      return typeInvolvesPromise(resolved, env, visited);
    }
  }
  return false;
}
function substituteTypeParams(type, bindings) {
  if (bindings.size === 0)
    return type;
  switch (type.kind) {
    case "typevar": {
      const bound = bindings.get(type.name);
      return bound ?? type;
    }
    case "ref": {
      const bound = bindings.get(type.name);
      if (bound)
        return bound;
      if (type.args && type.args.length > 0) {
        return Types.ref(type.name, type.args.map((a) => substituteTypeParams(a, bindings)));
      }
      return type;
    }
    case "list":
      return Types.list(substituteTypeParams(type.elementType, bindings));
    case "map":
      return Types.map(substituteTypeParams(type.keyType, bindings), substituteTypeParams(type.valueType, bindings));
    case "set":
      return Types.set(substituteTypeParams(type.elementType, bindings));
    case "promise":
      return Types.promise(substituteTypeParams(type.resolveType, bindings));
    case "channel":
      return Types.channel(substituteTypeParams(type.elementType, bindings));
    case "optional":
      return Types.optional(substituteTypeParams(type.inner, bindings));
    case "tuple":
      return Types.tuple(...type.elements.map((e) => substituteTypeParams(e, bindings)));
    case "union":
      return Types.union(...type.types.map((t) => substituteTypeParams(t, bindings)));
    case "intersection":
      return Types.intersection(...type.types.map((t) => substituteTypeParams(t, bindings)));
    case "generic":
      return Types.generic(substituteTypeParams(type.base, bindings), type.args.map((a) => substituteTypeParams(a, bindings)));
    case "function":
      return Types.fn(type.params.map((p) => Types.param(p.name, substituteTypeParams(p.type, bindings), p.optional, p.rest)), substituteTypeParams(type.returnType, bindings));
    case "stream":
      return Types.stream(substituteTypeParams(type.elementType, bindings));
    case "result":
      return Types.result(substituteTypeParams(type.okType, bindings), substituteTypeParams(type.errType, bindings));
    default:
      return type;
  }
}
function substituteTypeInObject(objType, bindings) {
  if (bindings.size === 0)
    return objType;
  const result = {
    kind: "object",
    name: objType.name,
    properties: objType.properties.map((p) => ({
      ...p,
      type: substituteTypeParams(p.type, bindings)
    })),
    methods: objType.methods.map((m) => ({
      name: m.name,
      type: {
        ...m.type,
        params: m.type.params.map((p) => ({
          ...p,
          type: substituteTypeParams(p.type, bindings)
        })),
        returnType: substituteTypeParams(m.type.returnType, bindings)
      }
    })),
    typeParams: objType.typeParams,
    alias: objType.alias,
    context: objType.context
  };
  return result;
}
function unifyTypes(paramType, argType, bindings) {
  if (paramType.kind === "typevar") {
    const existing = bindings.get(paramType.name);
    if (existing === undefined)
      return;
    if (existing.kind === "unknown") {
      bindings.set(paramType.name, argType);
    } else if (existing.kind !== "typevar" || existing.name !== paramType.name) {
      unifyTypes(existing, argType, bindings);
    }
    return;
  }
  if (paramType.kind === "ref" && bindings.has(paramType.name)) {
    const existing = bindings.get(paramType.name);
    if (existing === undefined)
      return;
    if (existing.kind === "unknown") {
      bindings.set(paramType.name, argType);
    } else if (existing.kind !== "ref" || existing.name !== paramType.name) {
      unifyTypes(existing, argType, bindings);
    }
    return;
  }
  if (paramType.kind === "list" && argType.kind === "list") {
    unifyTypes(paramType.elementType, argType.elementType, bindings);
  } else if (paramType.kind === "map" && argType.kind === "map") {
    unifyTypes(paramType.keyType, argType.keyType, bindings);
    unifyTypes(paramType.valueType, argType.valueType, bindings);
  } else if (paramType.kind === "set" && argType.kind === "set") {
    unifyTypes(paramType.elementType, argType.elementType, bindings);
  } else if (paramType.kind === "tuple" && argType.kind === "tuple") {
    const len = Math.min(paramType.elements.length, argType.elements.length);
    for (let i = 0;i < len; i++) {
      unifyTypes(paramType.elements[i], argType.elements[i], bindings);
    }
  } else if (paramType.kind === "generic" && argType.kind === "generic") {
    unifyTypes(paramType.base, argType.base, bindings);
    const len = Math.min(paramType.args.length, argType.args.length);
    for (let i = 0;i < len; i++) {
      unifyTypes(paramType.args[i], argType.args[i], bindings);
    }
  } else if (paramType.kind === "promise" && argType.kind === "promise") {
    unifyTypes(paramType.resolveType, argType.resolveType, bindings);
  } else if (paramType.kind === "channel" && argType.kind === "channel") {
    unifyTypes(paramType.elementType, argType.elementType, bindings);
  } else if (paramType.kind === "optional" && argType.kind === "optional") {
    unifyTypes(paramType.inner, argType.inner, bindings);
  } else if (paramType.kind === "function" && argType.kind === "function") {
    for (let i = 0;i < paramType.params.length && i < argType.params.length; i++) {
      unifyTypes(paramType.params[i].type, argType.params[i].type, bindings);
    }
    unifyTypes(paramType.returnType, argType.returnType, bindings);
  }
}

// src/builtin/extractor.ts
function astTypeToType2(typeExpr) {
  if (!typeExpr)
    return Types.unknown;
  switch (typeExpr.kind) {
    case "NamedType":
      return nameToType(typeExpr.name);
    case "GenericType": {
      const args = typeExpr.args.map(astTypeToType2);
      const constructed = constructGenericType(typeExpr.name, args);
      if (constructed) {
        return constructed;
      }
      return Types.generic(nameToType(typeExpr.name), args);
    }
    case "FunctionType": {
      const params = typeExpr.params.map((p, i) => Types.param(`arg${i}`, astTypeToType2(p)));
      return Types.fn(params, astTypeToType2(typeExpr.returnType));
    }
    case "UnionType":
      return Types.union(...typeExpr.types.map(astTypeToType2));
    case "OptionalType":
      return Types.optional(astTypeToType2(typeExpr.inner));
    case "ListType":
      return Types.list(astTypeToType2(typeExpr.elementType));
    case "MapType":
      return Types.map(astTypeToType2(typeExpr.keyType), astTypeToType2(typeExpr.valueType));
    default:
      return Types.unknown;
  }
}
function nameToType(name) {
  return PRIMITIVE_TYPE_MAP[name] ?? Types.ref(name);
}
function extractFunctionType(decl) {
  const typeParams = decl.typeParams?.map((p) => ({
    name: p.name,
    constraint: p.constraint ? astTypeToType2(p.constraint) : undefined
  }));
  const params = decl.params.map((p) => Types.param(p.name, astTypeToType2(p.type), p.optional, p.rest));
  const returnType = astTypeToType2(decl.returnType);
  const isGenerator = decl.kind === "FnDecl" ? decl.isGenerator : false;
  return {
    kind: "function",
    typeParams,
    params,
    returnType,
    isGenerator,
    context: []
  };
}
function extractObjectType(decl) {
  const properties = [];
  const methods = [];
  for (const member of decl.body?.members || []) {
    if (member.kind === "FieldDecl") {
      properties.push({
        name: member.name,
        type: astTypeToType2(member.type),
        optional: member.optional,
        computed: member.computed,
        defaultValue: !!member.defaultValue
      });
    } else if (member.kind === "MethodDecl") {
      const methodTypeParams = member.typeParams?.map((p) => ({
        name: p.name,
        constraint: p.constraint ? astTypeToType2(p.constraint) : undefined
      }));
      const methodParams = member.params.map((p) => Types.param(p.name, astTypeToType2(p.type), p.optional, p.rest));
      const fnType = Types.fn(methodParams, astTypeToType2(member.returnType));
      if (methodTypeParams) {
        fnType.typeParams = methodTypeParams;
      }
      methods.push({
        name: member.name,
        type: fnType
      });
    }
  }
  const typeParams = decl.typeParams?.map((p) => ({
    name: p.name,
    constraint: p.constraint ? astTypeToType2(p.constraint) : undefined
  }));
  const aliasTypes = decl.alias?.map((e) => astTypeToType2(e));
  return {
    kind: "object",
    name: decl.name,
    properties,
    methods,
    typeParams,
    alias: aliasTypes
  };
}
var BUILTIN_TYPE_KIND_MAP = {
  string: "string",
  list: "list",
  map: "map",
  set: "set",
  Channel: "channel"
};
function extractBuiltinsTypes(program) {
  const functions = new Map;
  const types = new Map;
  const externTypes = new Set;
  const builtinMethods = new Map;
  for (const stmt of program.body) {
    switch (stmt.kind) {
      case "FnDecl":
        functions.set(stmt.name, extractFunctionType(stmt));
        break;
      case "ExternFnDecl":
        functions.set(stmt.name, extractFunctionType(stmt));
        break;
      case "InterfaceDecl": {
        const methods = [];
        for (const member of stmt.body.members) {
          if (member.kind === "MethodDecl") {
            methods.push({ name: member.name, type: methodToFunctionType(member) });
          }
        }
        const iface = {
          kind: "interface",
          name: stmt.name,
          methods,
          typeParams: stmt.typeParams?.map((p) => ({
            name: p.name,
            constraint: p.constraint ? astTypeToType2(p.constraint) : undefined
          }))
        };
        types.set(stmt.name, iface);
        break;
      }
      case "TypeDecl": {
        const objType = extractObjectType(stmt);
        types.set(stmt.name, objType);
        if (stmt.isExtern) {
          externTypes.add(stmt.name);
          const typeKind = BUILTIN_TYPE_KIND_MAP[stmt.name];
          if (typeKind) {
            const memberMap = new Map;
            for (const prop of objType.properties) {
              memberMap.set(prop.name, {
                type: prop.type,
                isProperty: true
              });
            }
            for (const method of objType.methods) {
              memberMap.set(method.name, {
                type: method.type,
                isProperty: false
              });
            }
            builtinMethods.set(typeKind, memberMap);
          }
        }
        break;
      }
    }
  }
  return { functions, types, externTypes, builtinMethods };
}
function getStdlibFunctionNames(program) {
  const result = new Set;
  for (const stmt of program.body) {
    if (stmt.kind === "FnDecl" || stmt.kind === "ExternFnDecl") {
      result.add(stmt.name);
    }
  }
  return result;
}
function getExternFunctionNames(program) {
  const result = new Set;
  for (const stmt of program.body) {
    if (stmt.kind === "ExternFnDecl") {
      result.add(stmt.name);
    }
  }
  return result;
}
function getExternTypeNames(program) {
  const result = new Set;
  for (const stmt of program.body) {
    if (stmt.kind === "TypeDecl" && stmt.isExtern) {
      result.add(stmt.name);
    }
  }
  return result;
}

// src/builtin/builtins.ms
var builtins_default = `// ============================================
// Manuscript Builtins
// ============================================

// ============================================
// Closable (for with/using)
// ============================================

interface Closable
  fn close(): void

// ============================================
// Primitive Type Methods (built-in)
// ============================================

extern type string
  length: number
  fn upper(): string
  fn lower(): string
  fn trim(): string
  fn split(sep: string): list[string]
  fn contains(s: string): bool
  fn starts_with(prefix: string): bool
  fn ends_with(suffix: string): bool
  fn replace(old: string, new: string): string
  fn slice(start: number, end?: number): string
  fn char_at(index: number): string?
  fn index_of(s: string): number?
  fn repeat(n: number): string
  fn pad_start(len: number, char?: string): string
  fn pad_end(len: number, char?: string): string
  fn chars(): list[string]

extern type list[T]
  length: number
  fn push(item: T): list[T]
  fn pop(): T?
  fn shift(): T?
  fn contains(item: T): bool
  fn index_of(item: T): number?
  fn join(sep?: string): string
  fn reverse(): list[T]
  fn slice(start: number, end?: number): list[T]
  fn map[U](f: fn(T): U): list[U]
  fn filter(f: fn(T): bool): list[T]
  fn reduce[U](f: fn(U, T): U, init: U): U
  fn find(f: fn(T): bool): T?
  fn every(f: fn(T): bool): bool
  fn some(f: fn(T): bool): bool
  fn first(): T?
  fn last(): T?
  fn is_empty(): bool
  fn sort(cmp?: fn(T, T): number): list[T]

extern type map[K, V]
  size: number
  fn get(key: K): V?
  fn set(key: K, value: V): void
  fn has(key: K): bool
  fn delete(key: K): bool
  fn keys(): list[K]
  fn values(): list[V]
  fn entries(): list[list[unknown]]
  fn clear(): void

extern type set[T]
  size: number
  fn add(item: T): set[T]
  fn has(item: T): bool
  fn delete(item: T): bool
  fn clear(): void
  fn values(): list[T]
  fn entries(): list[list[T]]
  fn keys(): list[T]
  fn forEach(f: fn(T): void): void

// ============================================
// Built-in Types
// ============================================

type Error
  message: string
  cause: Error?
  stack: string?

extern type Context
  fn exit(): void

// ============================================
// Async Types
// ============================================

extern type Promise[T]
extern type Stream[T]

// ============================================
// Intrinsic Functions
// ============================================

// I/O
extern fn print(...args: unknown): void
extern fn log(...args: unknown): void

// Type operations
extern fn typeof[T](x: T): string
extern fn clone[T](x: T): T
extern fn hash[T](x: T): number

// Conversion
extern fn to_str[T](x: T): string
extern fn to_num(s: string): number
extern fn to_json[T](x: T): string
extern fn from_json[T](s: string): T

// Time
extern fn now(): number

// Collections
extern fn len[T](x: T): number

// Errors
extern fn panic(message: string): never
extern fn error(message: string, cause?: Error): Error

// String functions
extern fn upper(s: string): string
extern fn lower(s: string): string
extern fn trim(s: string): string
extern fn split(s: string, delim: string): list[string]
extern fn join(list: list[string], delim: string): string
extern fn replace(s: string, old: string, replacement: string): string
extern fn starts_with(s: string, prefix: string): bool
extern fn ends_with(s: string, suffix: string): bool
extern fn substring(s: string, start: number, end?: number): string
extern fn matches(s: string, pattern: string): bool

// Set functions
extern fn set[T](list: list[T]): set[T]
extern fn union[T](a: set[T], b: set[T]): set[T]
extern fn intersect[T](a: set[T], b: set[T]): set[T]
extern fn difference[T](a: set[T], b: set[T]): set[T]
extern fn is_subset[T](a: set[T], b: set[T]): bool

// ============================================
// Pure Functions
// ============================================

// Result type for error handling
type Result[T, E]
  ok: bool
  value?: T
  error?: E

fn ok[T](value: T): Result[T, never]
  Result(ok: true, value: value)

fn err[E](error: E): Result[never, E]
  Result(ok: false, error: error)

fn assert(condition: bool, message?: string): void
  if not condition
    panic(message ?? "Assertion failed")

fn equals[T](a: T, b: T): bool
  to_json(a) == to_json(b)
`;

// src/builtin/index.ts
var builtinsSource = builtins_default;

// src/shared/stdlib.ts
var builtinsProgram = new Parser(builtinsSource).parse();
var STDLIB_FUNCTIONS = getStdlibFunctionNames(builtinsProgram);
var EXTERN_FUNCTIONS = getExternFunctionNames(builtinsProgram);
var EXTERN_TYPES = getExternTypeNames(builtinsProgram);
var PRIMITIVE_EXTERN_TYPES = new Set(["string", "list", "map", "set"]);

// src/stdlib/loader.ts
import { readFileSync, readdirSync } from "fs";

// src/types/errors.ts
class TypeCheckError extends Error {
  loc;
  hint;
  constructor(message, loc, hint) {
    super(`${message} at line ${loc.line}, column ${loc.column}`);
    this.loc = loc;
    this.hint = hint;
    this.name = "TypeCheckError";
  }
}

// src/stdlib/loader.ts
var STDLIB_DIR = import.meta.dir;
var sourceCache = new Map;
var astCache = new Map;
var typesCache = new Map;
var embeddedIndex = null;
function getEmbeddedIndex() {
  if (!embeddedIndex) {
    embeddedIndex = new Map;
    if (typeof Bun !== "undefined" && Bun.embeddedFiles) {
      for (const blob of Bun.embeddedFiles) {
        embeddedIndex.set(blob.name, blob);
      }
    }
  }
  return embeddedIndex;
}
function getStdlibSourceSync(name) {
  if (sourceCache.has(name))
    return sourceCache.get(name);
  try {
    const source = readFileSync(`${STDLIB_DIR}/${name}.ms`, "utf-8");
    sourceCache.set(name, source);
    return source;
  } catch {
    return null;
  }
}
function getStdlibAST(name) {
  if (astCache.has(name))
    return astCache.get(name);
  const source = getStdlibSourceSync(name);
  if (!source)
    return null;
  const ast2 = new Parser(source).parse();
  astCache.set(name, ast2);
  return ast2;
}
function getStdlibTypes(name) {
  if (typesCache.has(name))
    return typesCache.get(name);
  const ast2 = getStdlibAST(name);
  if (!ast2)
    return null;
  const types = extractBuiltinsTypes(ast2);
  typesCache.set(name, types);
  return types;
}
function resolveStdlibImports(program, env) {
  const errors = [];
  const loc0 = { line: 0, column: 0, offset: 0 };
  for (const decl of program.body) {
    if (decl.kind !== "ImportDecl" || !isStdlibImport(decl.source))
      continue;
    const modName = stdlibModuleName(decl.source);
    const stdTypes = getStdlibTypes(modName);
    if (!stdTypes) {
      errors.push(new TypeCheckError(`Stdlib module not found: "${decl.source}"`, decl.loc ?? loc0));
      continue;
    }
    if (stdTypes.builtinMethods.size > 0) {
      env.mergeBuiltinMethods(stdTypes.builtinMethods);
    }
    for (const { name, alias } of decl.names) {
      const type = stdTypes.functions.get(name) ?? stdTypes.types.get(name);
      if (!type) {
        errors.push(new TypeCheckError(`Module "${decl.source}" does not export "${name}".`, decl.loc ?? loc0));
        continue;
      }
      try {
        if (stdTypes.types.has(name))
          env.defineType(alias ?? name, type);
        else
          env.define(alias ?? name, type, false);
      } catch {
        errors.push(new TypeCheckError(`Cannot import "${name}": shadows builtin; use an alias.`, decl.loc ?? loc0));
      }
    }
  }
  return errors;
}
function isStdlibExternType(name) {
  for (const types of typesCache.values()) {
    if (types.externTypes.has(name))
      return true;
  }
  return false;
}
function getAllStdlibSources() {
  const result = new Map;
  const idx = getEmbeddedIndex();
  for (const [filename] of idx) {
    if (filename.endsWith(".ms")) {
      const modName = filename.replace(/\.ms$/, "");
      const src = getStdlibSourceSync(modName);
      if (src)
        result.set(modName, src);
    }
  }
  if (result.size > 0)
    return result;
  try {
    for (const file of readdirSync(STDLIB_DIR)) {
      if (file.endsWith(".ms")) {
        const modName = file.replace(/\.ms$/, "");
        const src = getStdlibSourceSync(modName);
        if (src)
          result.set(modName, src);
      }
    }
  } catch {}
  return result;
}
function isStdlibImport(specifier) {
  return specifier.startsWith("std/");
}
function stdlibModuleName(specifier) {
  return specifier.slice(4);
}

// src/codegen/expressions.ts
var _gen;
function setGen(fn) {
  _gen = fn;
}
function gen(ctx, node, opts) {
  return _gen(ctx, node, opts);
}
function genExpr(ctx, expr, opts) {
  switch (expr.kind) {
    case "Literal":
      return genLiteral(expr);
    case "Identifier":
      return genIdentifier(expr, opts);
    case "BinaryExpr":
      return genBinary(ctx, expr, opts);
    case "UnaryExpr":
      return genUnary(ctx, expr, opts);
    case "CallExpr":
      return genCall(ctx, expr, opts);
    case "IndexExpr":
      return genIndex(ctx, expr, opts);
    case "MemberExpr":
      return genMember(ctx, expr, opts);
    case "PipeExpr":
      return genPipe(ctx, expr, opts);
    case "LambdaExpr":
      return genLambda(ctx, expr, opts);
    case "IfExpr":
      return genIfExpr(ctx, expr, opts);
    case "MatchExpr":
      return genMatchExpr(ctx, expr, opts);
    case "ListExpr":
      return genList(ctx, expr, opts);
    case "SetExpr":
      return genSet(ctx, expr, opts);
    case "MapExpr":
      return genMap(ctx, expr, opts);
    case "TemplateLiteral":
      return genTemplate(ctx, expr, opts);
    case "SpawnExpr":
      return genSpawn(ctx, expr, opts);
    case "TypeAssertion":
      return genExpr(ctx, expr.expr, opts);
    case "NullAssertion":
      return genExpr(ctx, expr.expr, opts);
    case "RangeExpr":
      return genRange(ctx, expr, opts);
  }
}
function genLiteral(node) {
  if (node.value === null)
    return "null";
  if (typeof node.value === "string")
    return JSON.stringify(node.value);
  if (typeof node.value === "boolean")
    return node.value ? "true" : "false";
  return String(node.value);
}
function genIdentifier(node, opts) {
  if (isTypeConstructor(node)) {
    return node.name;
  }
  if (opts.classFields?.has(node.name)) {
    const prefix = opts.selfVar || "this";
    return `${prefix}.${node.name}`;
  }
  return node.name;
}
function genBinary(ctx, node, opts) {
  const left = genExpr(ctx, node.left, opts);
  const right = genExpr(ctx, node.right, opts);
  switch (node.op) {
    case "and":
      return `(${left} && ${right})`;
    case "or":
      return `(${left} || ${right})`;
    case "^":
      return `Math.pow(${left}, ${right})`;
    case "is":
      return `(${left} instanceof ${right})`;
    case "??":
      return `(${left} ?? ${right})`;
    default:
      return `(${left} ${node.op} ${right})`;
  }
}
function genUnary(ctx, node, opts) {
  const operand = genExpr(ctx, node.operand, opts);
  if (node.op === "not")
    return `!${operand}`;
  return `${node.op}${operand}`;
}
function genCall(ctx, node, opts) {
  let callee = genExpr(ctx, node.callee, opts);
  if (node.callee.kind === "Identifier" && STDLIB_FUNCTIONS.has(node.callee.name) && !opts.classFields?.has(node.callee.name)) {
    callee = `__ms_runtime.${node.callee.name}`;
  }
  if (node.callee.kind === "IndexExpr" && node.callee.object.kind === "Identifier") {
    const baseName = node.callee.object.name;
    const args2 = genCallArgs(ctx, node.args, opts);
    const isExtern = EXTERN_TYPES.has(baseName) || isStdlibExternType(baseName);
    if (isExtern && !PRIMITIVE_EXTERN_TYPES.has(baseName)) {
      return `new __ms_runtime.${baseName}(${args2})`;
    }
    if (isTypeConstructor(node.callee.object) || ctx.typeFields.has(baseName)) {
      return `${baseName}(${args2})`;
    }
  }
  if (node.callee.kind === "Identifier" && (EXTERN_TYPES.has(node.callee.name) || isStdlibExternType(node.callee.name)) && !STDLIB_FUNCTIONS.has(node.callee.name) && !PRIMITIVE_EXTERN_TYPES.has(node.callee.name)) {
    const args2 = genCallArgs(ctx, node.args, opts);
    return `new __ms_runtime.${node.callee.name}(${args2})`;
  }
  if (node.callee.kind === "MemberExpr" && node.args.length === 0) {
    const objType = node.callee.object.resolvedType;
    if (objType?.kind === "set" && ["values", "entries", "keys"].includes(node.callee.property)) {
      const obj = genExpr(ctx, node.callee.object, opts);
      const method = node.callee.property;
      return `Array.from(${obj}.${method}())`;
    }
  }
  const paramOrder = getParamOrder(node.callee);
  const args = genCallArgs(ctx, node.args, opts, paramOrder);
  if (isTypeConstructor(node.callee)) {
    return `${callee}(${args})`;
  }
  if (node.callee.kind === "Identifier" && ctx.typeFields.has(node.callee.name)) {
    return `${callee}(${args})`;
  }
  return `(await ${callee}(${args}))`;
}
function genCallArgs(ctx, args, opts, paramOrder) {
  const hasNamed = args.some((a) => ("name" in a) && ("value" in a));
  if (hasNamed && paramOrder && paramOrder.length > 0) {
    const byName = new Map;
    const positional = [];
    for (const a of args) {
      if ("name" in a && "value" in a) {
        byName.set(a.name, a.value);
      } else {
        positional.push(a);
      }
    }
    let posIdx = 0;
    const ordered = paramOrder.map((name) => {
      if (byName.has(name))
        return byName.get(name);
      if (posIdx < positional.length)
        return positional[posIdx++];
      return null;
    });
    let lastProvided = ordered.length - 1;
    while (lastProvided >= 0 && ordered[lastProvided] === null) {
      lastProvided--;
    }
    const result = ordered.slice(0, lastProvided + 1).map((e) => e === null ? "undefined" : genExpr(ctx, e, opts));
    return result.join(", ");
  }
  if (hasNamed) {
    const parts = [];
    for (const arg of args) {
      if ("name" in arg && "value" in arg) {
        parts.push(`${arg.name}: ${genExpr(ctx, arg.value, opts)}`);
      } else {
        parts.push(genExpr(ctx, arg, opts));
      }
    }
    return `{ ${parts.join(", ")} }`;
  }
  return args.map((a) => genExpr(ctx, a, opts)).join(", ");
}
function genIndex(ctx, node, opts) {
  const obj = genExpr(ctx, node.object, opts);
  if (node.slice) {
    const start = node.slice.start ? genExpr(ctx, node.slice.start, opts) : "0";
    const end = node.slice.end ? genExpr(ctx, node.slice.end, opts) : "";
    if (node.optional)
      return `${obj}?.slice(${start}, ${end})`;
    return `${obj}.slice(${start}, ${end})`;
  }
  const index = genExpr(ctx, node.index, opts);
  if (node.optional)
    return `${obj}?.[${index}]`;
  return `${obj}[${index}]`;
}
function genMember(ctx, node, opts) {
  const obj = genExpr(ctx, node.object, opts);
  if (node.optional)
    return `${obj}?.${node.property}`;
  return `${obj}.${node.property}`;
}
function genPipe(ctx, node, opts) {
  const left = genExpr(ctx, node.left, opts);
  const right = node.right;
  if (right.kind === "CallExpr") {
    let callee = genExpr(ctx, right.callee, opts);
    if (right.callee.kind === "Identifier" && STDLIB_FUNCTIONS.has(right.callee.name)) {
      callee = `__ms_runtime.${right.callee.name}`;
    }
    const args = [left, ...right.args.map((a) => genExpr(ctx, a, opts))];
    return `(await ${callee}(${args.join(", ")}))`;
  } else if (right.kind === "Identifier") {
    const fnName = STDLIB_FUNCTIONS.has(right.name) ? `__ms_runtime.${right.name}` : right.name;
    return `(await ${fnName}(${left}))`;
  }
  return `(await (${genExpr(ctx, right, opts)})(${left}))`;
}
function genLambda(ctx, node, opts) {
  const params = node.params.map((p) => {
    let param = p.name;
    if (p.rest)
      param = `...${param}`;
    if (p.defaultValue)
      param += ` = ${genExpr(ctx, p.defaultValue, opts)}`;
    return param;
  }).join(", ");
  if (node.body.kind === "Block") {
    const bodyLines = [];
    pushIndent(ctx);
    for (const stmt of node.body.statements) {
      const prevOut = ctx.out;
      ctx.out = [];
      gen(ctx, stmt, opts);
      bodyLines.push(...ctx.out);
      ctx.out = prevOut;
    }
    popIndent(ctx);
    const indentStr = ctx.options.indent.repeat(ctx.indent);
    return `async (${params}) => {
${bodyLines.join(`
`)}
${indentStr}}`;
  }
  return `async (${params}) => ${genExpr(ctx, node.body, opts)}`;
}
function genIfExpr(ctx, node, opts) {
  const cond = genExpr(ctx, node.condition, opts);
  const then = genExpr(ctx, node.then, opts);
  const elseExpr = genExpr(ctx, node.else, opts);
  return `(${cond} ? ${then} : ${elseExpr})`;
}
function genMatchExpr(ctx, node, opts) {
  const value = genExpr(ctx, node.value, opts);
  const tv = tempVar(ctx, "_m");
  let code = `((_${tv}) => {
`;
  for (const arm of node.arms) {
    const condition = genPatternCondition(`_${tv}`, arm.pattern);
    code += `  if (${condition}) {
`;
    if (arm.pattern.kind === "IdentifierPattern") {
      code += `    const ${arm.pattern.name} = _${tv};
`;
    }
    if (arm.body.kind === "Block") {
      code += `    // block body
`;
    } else {
      code += `    return ${genExpr(ctx, arm.body, opts)};
`;
    }
    code += `  }
`;
  }
  code += `})(${value})`;
  return code;
}
function genPatternCondition(tempVar2, pattern) {
  switch (pattern.kind) {
    case "WildcardPattern":
      return "true";
    case "IdentifierPattern":
      return "true";
    case "LiteralPattern":
      return `${tempVar2} === ${JSON.stringify(pattern.value)}`;
    case "TypePattern": {
      const typeName = pattern.type.kind === "NamedType" ? pattern.type.name : "Object";
      return `(${tempVar2}?.__typename === "${typeName}" || ${tempVar2} instanceof ${typeName})`;
    }
    case "RangePattern":
      return `${tempVar2} >= ${pattern.start} && ${tempVar2} <= ${pattern.end}`;
    case "ArrayPattern":
      return `Array.isArray(${tempVar2})`;
    case "ObjectPattern":
      return `typeof ${tempVar2} === "object" && ${tempVar2} !== null`;
    default:
      return "true";
  }
}
function genList(ctx, node, opts) {
  const elements = node.elements.map((el) => {
    if (el.kind === "SpreadElement") {
      return `...${genExpr(ctx, el.expr, opts)}`;
    }
    return genExpr(ctx, el, opts);
  });
  return `[${elements.join(", ")}]`;
}
function genSet(ctx, node, opts) {
  if (node.elements.length === 0)
    return "new Set()";
  const inner = node.elements.map((el) => genExpr(ctx, el, opts)).join(", ");
  return `new Set([${inner}])`;
}
function genMap(ctx, node, opts) {
  if (node.entries.length === 0)
    return "Object.create(null)";
  const literalParts = [];
  const spreadExprs = [];
  for (const entry of node.entries) {
    if (entry.spread) {
      spreadExprs.push(genExpr(ctx, entry.key, opts));
    } else {
      const key = entry.key.kind === "Identifier" ? entry.key.name : `[${genExpr(ctx, entry.key, opts)}]`;
      const value = genExpr(ctx, entry.value, opts);
      literalParts.push(`${key}: ${value}`);
    }
  }
  const sources = [...spreadExprs];
  if (literalParts.length > 0)
    sources.push(`{ ${literalParts.join(", ")} }`);
  return sources.length === 0 ? "Object.create(null)" : `Object.assign(Object.create(null), ${sources.join(", ")})`;
}
function genTemplate(ctx, node, opts) {
  const parts = node.parts.map((p) => {
    if (typeof p === "string")
      return JSON.stringify(p);
    return `__ms_runtime.to_str(${genExpr(ctx, p.expr, opts)})`;
  });
  return parts.length === 1 ? parts[0] : `(${parts.join(" + ")})`;
}
function genSpawn(ctx, node, opts) {
  const inner = genExpr(ctx, node.expr, opts);
  return `__ms_runtime.spawn(async () => ${inner})`;
}
function genRange(ctx, node, opts) {
  const start = genExpr(ctx, node.start, opts);
  const end = genExpr(ctx, node.end, opts);
  return `__ms_runtime.range(${start}, ${end}, ${node.inclusive})`;
}

// src/codegen/patterns.ts
function genPattern(pattern) {
  switch (pattern.kind) {
    case "IdentifierPattern":
      return pattern.name;
    case "ArrayPattern": {
      const elements = pattern.elements.map((el) => genPattern(el));
      return `[${elements.join(", ")}]`;
    }
    case "ObjectPattern": {
      const props = pattern.properties.map((p) => {
        if (p.pattern.kind === "IdentifierPattern" && p.pattern.name === p.key) {
          return p.key;
        }
        return `${p.key}: ${genPattern(p.pattern)}`;
      });
      return `{ ${props.join(", ")} }`;
    }
    case "RestPattern":
      return `...${pattern.name}`;
    default:
      return "_";
  }
}
function genPatternCondition2(tempVar2, pattern) {
  switch (pattern.kind) {
    case "WildcardPattern":
      return "true";
    case "IdentifierPattern":
      return "true";
    case "LiteralPattern":
      return `${tempVar2} === ${JSON.stringify(pattern.value)}`;
    case "TypePattern": {
      const typeName = pattern.type.kind === "NamedType" ? pattern.type.name : "Object";
      return `(${tempVar2}?.__typename === "${typeName}" || ${tempVar2} instanceof ${typeName})`;
    }
    case "RangePattern":
      return `${tempVar2} >= ${pattern.start} && ${tempVar2} <= ${pattern.end}`;
    case "ArrayPattern":
      return `Array.isArray(${tempVar2})`;
    case "ObjectPattern":
      return `typeof ${tempVar2} === "object" && ${tempVar2} !== null`;
    default:
      return "true";
  }
}
function genMatchCondition(ctx, tempVar2, pattern, guard, opts) {
  let condition = genPatternCondition2(tempVar2, pattern);
  if (guard) {
    if (pattern.kind === "IdentifierPattern") {
      condition = `${condition} && (((${pattern.name}) => (${genExpr(ctx, guard, opts)}))(${tempVar2}))`;
    } else {
      condition = `${condition} && (${genExpr(ctx, guard, opts)})`;
    }
  }
  return condition;
}
function genPatternBindings(ctx, tempVar2, pattern) {
  switch (pattern.kind) {
    case "IdentifierPattern":
      emit(ctx, `const ${pattern.name} = ${tempVar2};`);
      break;
    case "TypePattern":
      if (pattern.binding) {
        emit(ctx, `const ${pattern.binding} = ${tempVar2};`);
      }
      break;
    case "ArrayPattern":
      for (let i = 0;i < pattern.elements.length; i++) {
        const el = pattern.elements[i];
        if (!el)
          continue;
        if (el.kind === "IdentifierPattern") {
          emit(ctx, `const ${el.name} = ${tempVar2}[${i}];`);
        } else if (el.kind === "RestPattern") {
          emit(ctx, `const ${el.name} = ${tempVar2}.slice(${i});`);
        }
      }
      break;
    case "ObjectPattern":
      for (const prop of pattern.properties) {
        if (prop.pattern.kind === "IdentifierPattern") {
          emit(ctx, `const ${prop.pattern.name} = ${tempVar2}.${prop.key};`);
        }
      }
      break;
  }
}

// src/codegen/statements.ts
var _gen2;
function setGen2(fn) {
  _gen2 = fn;
}
function genLet(ctx, stmt, opts) {
  const pattern = genPattern(stmt.pattern);
  const value = genExpr(ctx, stmt.value, opts);
  emit(ctx, `const ${pattern} = ${value};`);
}
function genVar(ctx, stmt, opts) {
  const value = genExpr(ctx, stmt.value, opts);
  emit(ctx, `let ${stmt.name} = ${value};`);
}
function genAssign(ctx, stmt, opts) {
  const target = genExpr(ctx, stmt.target, opts);
  const value = genExpr(ctx, stmt.value, opts);
  emit(ctx, `${target} ${stmt.op} ${value};`);
}
function genIf(ctx, stmt, opts) {
  if (opts.implicitReturn) {
    genIfWithReturn(ctx, stmt, opts);
  } else {
    genIfNormal(ctx, stmt, opts);
  }
}
function genIfNormal(ctx, stmt, opts) {
  const cond = genExpr(ctx, stmt.condition, opts);
  emit(ctx, `if (${cond}) {`);
  pushIndent(ctx);
  if (stmt.then.kind === "Block") {
    genBlock(ctx, stmt.then, opts);
  } else {
    _gen2(ctx, stmt.then, opts);
  }
  popIndent(ctx);
  for (const elif of stmt.elseIfs) {
    const elifCond = genExpr(ctx, elif.condition, opts);
    emit(ctx, `} else if (${elifCond}) {`);
    pushIndent(ctx);
    genBlock(ctx, elif.body, opts);
    popIndent(ctx);
  }
  if (stmt.else) {
    emit(ctx, "} else {");
    pushIndent(ctx);
    genBlock(ctx, stmt.else, opts);
    popIndent(ctx);
  }
  emit(ctx, "}");
}
function genIfWithReturn(ctx, stmt, opts) {
  const cond = genExpr(ctx, stmt.condition, opts);
  emit(ctx, `if (${cond}) {`);
  pushIndent(ctx);
  if (stmt.then.kind === "Block") {
    genBlock(ctx, stmt.then, { ...opts, implicitReturn: true });
  } else if (stmt.then.kind === "ExprStmt") {
    const expr = stmt.then.expr.kind === "MapExpr" ? `(${genExpr(ctx, stmt.then.expr, opts)})` : genExpr(ctx, stmt.then.expr, opts);
    emit(ctx, `return ${expr};`);
  } else {
    _gen2(ctx, stmt.then, opts);
  }
  popIndent(ctx);
  for (const elif of stmt.elseIfs) {
    const elifCond = genExpr(ctx, elif.condition, opts);
    emit(ctx, `} else if (${elifCond}) {`);
    pushIndent(ctx);
    genBlock(ctx, elif.body, { ...opts, implicitReturn: true });
    popIndent(ctx);
  }
  if (stmt.else) {
    emit(ctx, "} else {");
    pushIndent(ctx);
    genBlock(ctx, stmt.else, { ...opts, implicitReturn: true });
    popIndent(ctx);
  }
  emit(ctx, "}");
}
function genFor(ctx, stmt, opts) {
  const loopOpts = { ...opts, implicitReturn: false };
  if (!stmt.pattern || !stmt.iterable) {
    emit(ctx, "while (true) {");
    pushIndent(ctx);
    genBlock(ctx, stmt.body, loopOpts);
    popIndent(ctx);
    emit(ctx, "}");
    return;
  }
  const pattern = genPattern(stmt.pattern);
  const iterable = genExpr(ctx, stmt.iterable, opts);
  if (stmt.iterable.kind === "RangeExpr") {
    const range = stmt.iterable;
    const start = genExpr(ctx, range.start, opts);
    const end = genExpr(ctx, range.end, opts);
    const cmp = range.inclusive ? "<=" : "<";
    emit(ctx, `for (let ${pattern} = ${start}; ${pattern} ${cmp} ${end}; ${pattern}++) {`);
  } else {
    emit(ctx, `for await (const ${pattern} of ${iterable}) {`);
  }
  pushIndent(ctx);
  genBlock(ctx, stmt.body, loopOpts);
  popIndent(ctx);
  emit(ctx, "}");
}
function genMatch(ctx, stmt, opts) {
  if (opts.implicitReturn) {
    genMatchWithReturn(ctx, stmt, opts);
  } else {
    genMatchNormal(ctx, stmt, opts);
  }
}
function genMatchNormal(ctx, stmt, opts) {
  const value = genExpr(ctx, stmt.value, opts);
  const tv = tempVar(ctx, "_match");
  emit(ctx, `const ${tv} = ${value};`);
  let first = true;
  for (const arm of stmt.arms) {
    const condition = genMatchCondition(ctx, tv, arm.pattern, arm.guard, opts);
    if (first) {
      emit(ctx, `if (${condition}) {`);
      first = false;
    } else {
      emit(ctx, `} else if (${condition}) {`);
    }
    pushIndent(ctx);
    genPatternBindings(ctx, tv, arm.pattern);
    if (arm.body.kind === "Block") {
      genBlock(ctx, arm.body, opts);
    } else {
      const expr = genExpr(ctx, arm.body, opts);
      emit(ctx, `${expr};`);
    }
    popIndent(ctx);
  }
  emit(ctx, "}");
}
function genMatchWithReturn(ctx, stmt, opts) {
  const value = genExpr(ctx, stmt.value, opts);
  const tv = tempVar(ctx, "_match");
  emit(ctx, `const ${tv} = ${value};`);
  let first = true;
  for (const arm of stmt.arms) {
    const condition = genMatchCondition(ctx, tv, arm.pattern, arm.guard, opts);
    if (first) {
      emit(ctx, `if (${condition}) {`);
      first = false;
    } else {
      emit(ctx, `} else if (${condition}) {`);
    }
    pushIndent(ctx);
    genPatternBindings(ctx, tv, arm.pattern);
    if (arm.body.kind === "Block") {
      genBlock(ctx, arm.body, { ...opts, implicitReturn: true });
    } else {
      const expr = genExpr(ctx, arm.body, opts);
      emit(ctx, `return ${expr};`);
    }
    popIndent(ctx);
  }
  emit(ctx, "}");
}
function genReturn(ctx, stmt, opts) {
  if (stmt.value) {
    emit(ctx, `return ${genExpr(ctx, stmt.value, opts)};`);
  } else {
    emit(ctx, "return;");
  }
}
function genYield(ctx, stmt, opts) {
  emit(ctx, `yield ${genExpr(ctx, stmt.value, opts)};`);
}
function genDefer(ctx, stmt) {
  addDefer(ctx, stmt.body);
}
function genTry(ctx, stmt, opts) {
  emit(ctx, "try {");
  pushIndent(ctx);
  genBlock(ctx, stmt.body, opts);
  popIndent(ctx);
  if (stmt.catch) {
    emit(ctx, `} catch (${stmt.catch.name}) {`);
    pushIndent(ctx);
    genBlock(ctx, stmt.catch.body, opts);
    popIndent(ctx);
  }
  emit(ctx, "}");
}
function genThrow(ctx, stmt, opts) {
  const value = genExpr(ctx, stmt.value, opts);
  emit(ctx, `throw ${value};`);
}
function genWith(ctx, stmt, opts) {
  emit(ctx, "{");
  pushIndent(ctx);
  pushScope(ctx);
  emit(ctx, "__ms_runtime.__pushContext();");
  const ctxNames = [];
  for (const ctxBinding of stmt.contexts) {
    const expr = genExpr(ctx, ctxBinding.expr, opts);
    let name;
    if (ctxBinding.name) {
      name = ctxBinding.name;
      emit(ctx, `const ${name} = ${expr};`);
    } else {
      name = tempVar(ctx, "__ctx");
      emit(ctx, `const ${name} = ${expr};`);
    }
    ctxNames.push(name);
    const typeName = getTypeName(ctxBinding.expr);
    if (typeName) {
      emit(ctx, `__ms_runtime.__setContext("${typeName}", ${name});`);
    }
  }
  emit(ctx, "try {");
  pushIndent(ctx);
  genBlock(ctx, stmt.body, opts);
  popIndent(ctx);
  emit(ctx, "} finally {");
  pushIndent(ctx);
  const defers = popScope(ctx);
  for (const defer of defers.reverse()) {
    _gen2(ctx, defer, opts);
  }
  for (const name of ctxNames) {
    emit(ctx, `if (${name}?.close) ${name}.close();`);
  }
  emit(ctx, "__ms_runtime.__popContext();");
  popIndent(ctx);
  emit(ctx, "}");
  popIndent(ctx);
  emit(ctx, "}");
}
function genExprStmt(ctx, stmt, opts) {
  if (stmt.expr.kind === "MapExpr") {
    emit(ctx, `(${genExpr(ctx, stmt.expr, opts)});`);
  } else {
    emit(ctx, `${genExpr(ctx, stmt.expr, opts)};`);
  }
}
function genBlock(ctx, block, opts) {
  const stmts = block.statements;
  for (let i = 0;i < stmts.length; i++) {
    const stmt = stmts[i];
    const isLast = i === stmts.length - 1;
    if (isLast && opts.implicitReturn && stmt) {
      if (stmt.kind === "ExprStmt") {
        const expr = stmt.expr.kind === "MapExpr" ? `(${genExpr(ctx, stmt.expr, opts)})` : genExpr(ctx, stmt.expr, opts);
        emit(ctx, `return ${expr};`);
        continue;
      }
      if (stmt.kind === "MatchStmt") {
        genMatchWithReturn(ctx, stmt, opts);
        continue;
      }
      if (stmt.kind === "IfStmt") {
        genIfWithReturn(ctx, stmt, opts);
        continue;
      }
      if (stmt.kind === "WithStmt") {
        genWith(ctx, stmt, { ...opts, implicitReturn: true });
        continue;
      }
    }
    if (stmt)
      _gen2(ctx, stmt, { ...opts, implicitReturn: false });
  }
}

// src/codegen/declarations.ts
function genParams(ctx, params, opts) {
  return params.map((p) => {
    let param = p.name;
    if (p.rest)
      param = `...${param}`;
    if (p.defaultValue) {
      param += ` = ${genExpr(ctx, p.defaultValue, opts)}`;
    }
    return param;
  }).join(", ");
}
function genImport(ctx, decl, opts) {
  if (isStdlibImport(decl.source)) {
    const items2 = decl.names.map((item) => {
      if (item.alias)
        return `${item.name}: ${item.alias}`;
      return item.name;
    });
    emit(ctx, `const { ${items2.join(", ")} } = __ms_runtime;`);
    return;
  }
  const items = decl.names.map((item) => {
    if (item.alias)
      return `${item.name} as ${item.alias}`;
    return item.name;
  });
  const path = ctx.options.importEmitPaths?.get(decl.source) ?? decl.source;
  if (ctx.options.module === "esm") {
    emit(ctx, `import { ${items.join(", ")} } from "${path}";`);
  } else {
    emit(ctx, `const { ${items.join(", ")} } = require("${path}");`);
  }
}
function genFn(ctx, decl, opts) {
  const params = genParams(ctx, decl.params, opts);
  const prefix = decl.isGenerator ? "function*" : "async function";
  emit(ctx, `${prefix} ${decl.name}(${params}) {`);
  pushIndent(ctx);
  if (decl.using && decl.using.bindings.length > 0) {
    for (const binding of decl.using.bindings) {
      const name = binding.name || tempVar(ctx, "_binding");
      const typeName = binding.type.kind === "NamedType" ? binding.type.name : "unknown";
      emit(ctx, `const ${name} = __ms_runtime.__getContext("${typeName}");`);
    }
  }
  genBlock(ctx, decl.body, { ...opts, implicitReturn: true });
  popIndent(ctx);
  emit(ctx, "}");
  emit(ctx, "");
}
function genType(ctx, decl, opts) {
  if (!decl.body) {
    emit(ctx, `// type ${decl.name} = ...`);
    return;
  }
  const fields = [];
  const methods = [];
  for (const member of decl.body.members) {
    if (member.kind === "FieldDecl") {
      fields.push(member);
    } else if (member.kind === "MethodDecl") {
      methods.push(member);
    }
  }
  const classFields = new Set(fields.map((f) => f.name));
  for (const method of methods) {
    classFields.add(method.name);
  }
  for (const field of fields) {
    if (field.embedded) {
      const embeddedFields2 = ctx.typeFields.get(field.name);
      if (embeddedFields2) {
        for (const ef of embeddedFields2) {
          classFields.add(ef);
        }
      }
    }
  }
  ctx.typeFields.set(decl.name, classFields);
  const methodOpts = { ...opts, classFields };
  if (methods.length > 0) {
    emit(ctx, `const ${decl.name}$methods = Object.assign(Object.create(null), {`);
    pushIndent(ctx);
    for (const method of methods) {
      const prefix = method.isGenerator ? "*" : "async ";
      const params = genParams(ctx, method.params, methodOpts);
      emit(ctx, `${prefix}${method.name}(${params}) {`);
      pushIndent(ctx);
      if (method.body) {
        genBlock(ctx, method.body, { ...methodOpts, implicitReturn: true });
      }
      popIndent(ctx);
      emit(ctx, `},`);
    }
    popIndent(ctx);
    emit(ctx, `});`);
    emit(ctx, "");
  }
  const embeddedFields = fields.filter((f) => f.embedded);
  if (fields.length > 0) {
    const allParams = fields.map((f) => {
      if (f.embedded) {
        const typeName = EXTERN_TYPES.has(f.name) ? `__ms_runtime.${f.name}` : f.name;
        return `_${f.name} = ${typeName}()`;
      } else if (f.optional || f.defaultValue || f.computed) {
        if (f.defaultValue)
          return `${f.name} = ${genExpr(ctx, f.defaultValue, opts)}`;
        return `${f.name} = undefined`;
      }
      return f.name;
    }).join(", ");
    emit(ctx, `function ${decl.name}(${allParams}) {`);
    pushIndent(ctx);
    if (methods.length > 0) {
      emit(ctx, `const self = Object.create(${decl.name}$methods);`);
    } else {
      emit(ctx, `const self = Object.create(null);`);
    }
    emit(ctx, `self.__typename = "${decl.name}";`);
    for (const field of fields) {
      if (field.embedded)
        continue;
      if (field.computed && field.defaultValue) {
        emit(ctx, `Object.defineProperty(self, "${field.name}", { get() { return ${genExpr(ctx, field.defaultValue, { ...opts, selfVar: "self" })}; } });`);
      } else {
        emit(ctx, `self.${field.name} = ${field.name};`);
      }
    }
    for (const ef of embeddedFields) {
      const paramName = `_${ef.name}`;
      emit(ctx, `self.${ef.name} = ${paramName};`);
      emit(ctx, `for (const k in ${paramName}) {`);
      pushIndent(ctx);
      emit(ctx, `if (k !== '__typename' && !(k in self)) {`);
      pushIndent(ctx);
      emit(ctx, `const v = ${paramName}[k];`);
      emit(ctx, `if (typeof v === 'function') {`);
      pushIndent(ctx);
      emit(ctx, `self[k] = v.bind(${paramName});`);
      popIndent(ctx);
      emit(ctx, `} else {`);
      pushIndent(ctx);
      emit(ctx, `Object.defineProperty(self, k, {`);
      pushIndent(ctx);
      emit(ctx, `get() { return self.${ef.name}[k]; },`);
      emit(ctx, `set(v) { self.${ef.name}[k] = v; },`);
      emit(ctx, `enumerable: true`);
      popIndent(ctx);
      emit(ctx, `});`);
      popIndent(ctx);
      emit(ctx, `}`);
      popIndent(ctx);
      emit(ctx, `}`);
      popIndent(ctx);
      emit(ctx, `}`);
    }
    emit(ctx, `return self;`);
    popIndent(ctx);
    emit(ctx, "}");
    emit(ctx, "");
  } else {
    emit(ctx, `function ${decl.name}() {`);
    pushIndent(ctx);
    if (methods.length > 0) {
      emit(ctx, `return Object.create(${decl.name}$methods);`);
    } else {
      emit(ctx, `return Object.create(null);`);
    }
    popIndent(ctx);
    emit(ctx, "}");
    emit(ctx, "");
  }
}
function genTest(ctx, decl, opts) {
  emit(ctx, `__ms_runtime.test(${JSON.stringify(decl.description)}, async () => {`);
  pushIndent(ctx);
  genBlock(ctx, decl.body, opts);
  popIndent(ctx);
  emit(ctx, "});");
  emit(ctx, "");
}

// src/codegen/codegen.ts
function gen2(ctx, node, opts) {
  switch (node.kind) {
    case "Literal":
    case "Identifier":
    case "BinaryExpr":
    case "UnaryExpr":
    case "CallExpr":
    case "IndexExpr":
    case "MemberExpr":
    case "PipeExpr":
    case "LambdaExpr":
    case "IfExpr":
    case "MatchExpr":
    case "ListExpr":
    case "SetExpr":
    case "MapExpr":
    case "TemplateLiteral":
    case "SpawnExpr":
    case "TypeAssertion":
    case "NullAssertion":
    case "RangeExpr":
      return genExpr(ctx, node, opts);
    case "ImportDecl":
      genImport(ctx, node, opts);
      return "";
    case "FnDecl":
      genFn(ctx, node, opts);
      return "";
    case "ExternFnDecl":
      return "";
    case "TypeDecl":
      genType(ctx, node, opts);
      return "";
    case "TestDecl":
      genTest(ctx, node, opts);
      return "";
    case "LetStmt":
      genLet(ctx, node, opts);
      return "";
    case "VarStmt":
      genVar(ctx, node, opts);
      return "";
    case "AssignStmt":
      genAssign(ctx, node, opts);
      return "";
    case "IfStmt":
      genIf(ctx, node, opts);
      return "";
    case "ForStmt":
      genFor(ctx, node, opts);
      return "";
    case "MatchStmt":
      genMatch(ctx, node, opts);
      return "";
    case "ReturnStmt":
      genReturn(ctx, node, opts);
      return "";
    case "YieldStmt":
      genYield(ctx, node, opts);
      return "";
    case "BreakStmt":
      emit(ctx, "break;");
      return "";
    case "ContinueStmt":
      emit(ctx, "continue;");
      return "";
    case "DeferStmt":
      genDefer(ctx, node);
      return "";
    case "TryStmt":
      genTry(ctx, node, opts);
      return "";
    case "ThrowStmt":
      genThrow(ctx, node, opts);
      return "";
    case "WithStmt":
      genWith(ctx, node, opts);
      return "";
    case "ExprStmt":
      genExprStmt(ctx, node, opts);
      return "";
    default:
      return "";
  }
}
setGen(gen2);
setGen2(gen2);
function emitRuntimeImports(ctx) {
  if (ctx.options.emitRuntimeImport) {
    emit(ctx, 'import { __ms_runtime } from "manuscript/runtime";');
    emit(ctx, "");
  }
}

class CodeGenerator {
  ctx;
  constructor(options = {}) {
    this.ctx = createCtx(options);
  }
  generate(program) {
    resetCtx(this.ctx);
    const opts = createOpts();
    emitRuntimeImports(this.ctx);
    for (const stmt of program.body) {
      gen2(this.ctx, stmt, opts);
    }
    return getOutput(this.ctx);
  }
}

// src/types/environment.ts
class TypeEnvironment {
  symbols = new Map;
  types = new Map;
  typeParams = new Map;
  parent;
  builtinMethods = null;
  constructor(parent = null) {
    this.parent = parent;
  }
  setBuiltinMethods(registry) {
    this.builtinMethods = registry;
  }
  mergeBuiltinMethods(registry) {
    if (!this.builtinMethods) {
      this.builtinMethods = new Map;
    }
    for (const [typeKind, members] of registry) {
      const existing = this.builtinMethods.get(typeKind);
      if (existing) {
        for (const [name, info] of members) {
          existing.set(name, info);
        }
      } else {
        this.builtinMethods.set(typeKind, new Map(members));
      }
    }
  }
  lookupBuiltinMethod(typeKind, memberName) {
    if (this.builtinMethods) {
      const members = this.builtinMethods.get(typeKind);
      if (members) {
        return members.get(memberName);
      }
    }
    if (this.parent) {
      return this.parent.lookupBuiltinMethod(typeKind, memberName);
    }
    return;
  }
  define(name, type, mutable = false) {
    if (this.symbols.has(name)) {
      throw new TypeError(`Variable '${name}' is already defined in this scope`);
    }
    this.symbols.set(name, { name, type, mutable, defined: true });
  }
  lookup(name) {
    const symbol = this.symbols.get(name);
    if (symbol)
      return symbol;
    if (this.parent)
      return this.parent.lookup(name);
    return;
  }
  isDefined(name) {
    return this.lookup(name) !== undefined;
  }
  getType(name) {
    return this.lookup(name)?.type;
  }
  isMutable(name) {
    return this.lookup(name)?.mutable ?? false;
  }
  defineType(name, type) {
    if (this.types.has(name)) {
      throw new TypeError(`Type '${name}' is already defined in this scope`);
    }
    this.types.set(name, type);
  }
  lookupType(name) {
    const type = this.types.get(name);
    if (type)
      return type;
    if (this.parent)
      return this.parent.lookupType(name);
    return;
  }
  resolveType(type) {
    if (type.kind === "generic" && type.base.kind === "ref") {
      const base = this.lookupType(type.base.name);
      if (base?.kind === "object" && base.typeParams?.length) {
        const bindings2 = new Map;
        for (let i = 0;i < base.typeParams.length && i < type.args.length; i++) {
          bindings2.set(base.typeParams[i].name, type.args[i]);
        }
        return substituteTypeInObject(base, bindings2);
      }
      return type;
    }
    if (type.kind !== "ref")
      return type;
    const resolved = this.lookupType(type.name);
    if (!resolved)
      return type;
    if (!type.args?.length)
      return resolved;
    const typeParams = resolved.kind === "object" ? resolved.typeParams : undefined;
    if (!typeParams?.length)
      return resolved;
    const bindings = new Map;
    for (let i = 0;i < typeParams.length && i < type.args.length; i++) {
      bindings.set(typeParams[i].name, type.args[i]);
    }
    if (resolved.kind === "object")
      return substituteTypeInObject(resolved, bindings);
    return substituteTypeParams(resolved, bindings);
  }
  bindTypeParam(name, type) {
    this.typeParams.set(name, type);
  }
  lookupTypeParam(name) {
    const type = this.typeParams.get(name);
    if (type)
      return type;
    if (this.parent)
      return this.parent.lookupTypeParam(name);
    return;
  }
  substitute(type) {
    switch (type.kind) {
      case "typevar": {
        const bound = this.lookupTypeParam(type.name);
        return bound ?? type;
      }
      case "list":
        return Types.list(this.substitute(type.elementType));
      case "map":
        return Types.map(this.substitute(type.keyType), this.substitute(type.valueType));
      case "set":
        return Types.set(this.substitute(type.elementType));
      case "optional":
        return Types.optional(this.substitute(type.inner));
      case "union":
        return Types.union(...type.types.map((t) => this.substitute(t)));
      case "function":
        return {
          ...type,
          params: type.params.map((p) => ({ ...p, type: this.substitute(p.type) })),
          returnType: this.substitute(type.returnType)
        };
      case "generic":
        return Types.generic(this.substitute(type.base), type.args.map((a) => this.substitute(a)));
      default:
        return type;
    }
  }
  child() {
    return new TypeEnvironment(this);
  }
  withContext(bindings) {
    const child = this.child();
    for (const binding of bindings) {
      if (binding.name) {
        child.define(binding.name, binding.type, false);
      }
    }
    return child;
  }
  getParent() {
    return this.parent;
  }
}
var builtinsTypesCache = null;
function getBuiltinsTypes() {
  if (!builtinsTypesCache) {
    const program = new Parser(builtinsSource).parse();
    builtinsTypesCache = extractBuiltinsTypes(program);
  }
  return builtinsTypesCache;
}
function createGlobalEnvironment() {
  const env = new TypeEnvironment;
  for (const [name, type] of Object.entries(PRIMITIVE_TYPE_MAP)) {
    env.defineType(name, type);
  }
  const builtins = getBuiltinsTypes();
  env.setBuiltinMethods(builtins.builtinMethods);
  const primitiveNames = new Set(Object.keys(PRIMITIVE_TYPE_MAP));
  for (const [name, type] of builtins.types) {
    if (primitiveNames.has(name))
      continue;
    env.defineType(name, type);
  }
  for (const [name, type] of builtins.functions) {
    env.define(name, type);
  }
  return env;
}

// src/types/passes/collect-declarations.ts
function collectDeclarations(input) {
  const { program, env } = input;
  const fnDecls = new Map;
  const errors = [];
  const addError = (message, loc, hint) => {
    errors.push(new TypeCheckError(message, loc, hint));
  };
  for (const stmt of program.body) {
    if (stmt.kind === "TypeDecl") {
      registerType(stmt, env, addError);
    } else if (stmt.kind === "InterfaceDecl") {
      registerInterface(stmt, env, addError);
    }
  }
  for (const stmt of program.body) {
    if (stmt.kind === "TypeDecl") {
      resolveEmbeddedTypes(stmt, env, addError);
    } else if (stmt.kind === "InterfaceDecl") {
      resolveEmbeddedInterfaces(stmt, env, addError);
    } else if (stmt.kind === "FnDecl") {
      collectFnDecl(stmt, env, fnDecls, addError);
    }
  }
  return { env, fnDecls, errors };
}
function registerType(decl, env, addError) {
  const properties = [];
  const methods = [];
  if (decl.body && decl.body.members.length > 0) {
    for (const member of decl.body.members) {
      if (member.kind === "FieldDecl") {
        if (RESERVED_PROPERTY_NAMES.has(member.name)) {
          const err = TypeErrors.reservedPropertyName(member.name);
          addError(err.message, member.loc, err.hint);
        }
        properties.push({
          name: member.name,
          type: member.type ? astTypeToType(member.type) : Types.unknown,
          optional: member.optional,
          computed: member.computed,
          defaultValue: !!member.defaultValue,
          embedded: member.embedded
        });
      } else if (member.kind === "MethodDecl") {
        if (RESERVED_PROPERTY_NAMES.has(member.name)) {
          const err = TypeErrors.reservedPropertyName(member.name);
          addError(err.message, member.loc, err.hint);
        }
        const methodType = methodToFunctionType(member);
        methods.push({ name: member.name, type: methodType });
      }
    }
  }
  const type = {
    kind: "object",
    name: decl.name,
    properties,
    methods,
    typeParams: decl.typeParams?.map((p) => ({
      name: p.name,
      constraint: p.constraint ? astTypeToType(p.constraint) : undefined
    })),
    alias: decl.alias?.map((e) => astTypeToType(e))
  };
  try {
    env.defineType(decl.name, type);
  } catch (e) {
    const err = TypeErrors.typeAlreadyDefined(decl.name);
    addError(err.message, decl.loc, err.hint);
  }
}
function registerInterface(decl, env, addError) {
  const methods = [];
  for (const member of decl.body.members) {
    if (member.kind === "MethodDecl") {
      if (RESERVED_PROPERTY_NAMES.has(member.name)) {
        const err = TypeErrors.reservedPropertyName(member.name);
        addError(err.message, member.loc, err.hint);
      }
      methods.push({ name: member.name, type: methodToFunctionType(member) });
    }
  }
  const iface = {
    kind: "interface",
    name: decl.name,
    methods,
    typeParams: decl.typeParams?.map((p) => ({
      name: p.name,
      constraint: p.constraint ? astTypeToType(p.constraint) : undefined
    }))
  };
  try {
    env.defineType(decl.name, iface);
  } catch (e) {
    const err = TypeErrors.typeAlreadyDefined(decl.name);
    addError(err.message, decl.loc, err.hint);
  }
}
function resolveEmbeddedInterfaces(decl, env, addError) {
  const iface = env.lookupType(decl.name);
  if (!iface || iface.kind !== "interface")
    return;
  const ownNames = new Set(iface.methods.map((m) => m.name));
  const promotedSources = new Map;
  for (const member of decl.body.members) {
    if (member.kind !== "EmbeddedInterfaceDecl")
      continue;
    const embedded = env.lookupType(member.name);
    if (!embedded) {
      addError(`Cannot embed '${member.name}': interface not found`, member.loc, `Make sure '${member.name}' is defined before '${decl.name}'`);
      continue;
    }
    if (embedded.kind !== "interface") {
      addError(`Cannot embed '${member.name}': not an interface`, member.loc, `Only interfaces can be embedded in an interface`);
      continue;
    }
    for (const method of embedded.methods) {
      if (ownNames.has(method.name))
        continue;
      const sources = promotedSources.get(method.name) || [];
      sources.push(member.name);
      promotedSources.set(method.name, sources);
      if (sources.length === 1) {
        iface.methods.push({ ...method, promotedFrom: member.name });
      }
    }
  }
  for (const [name, sources] of promotedSources) {
    if (sources.length > 1) {
      addError(`Ambiguous access to '${name}' - exists in: ${sources.join(", ")}`, decl.loc, `Use explicit access or define own method to disambiguate`);
    }
  }
}
function resolveEmbeddedTypes(decl, env, addError) {
  const type = env.lookupType(decl.name);
  if (!type || type.kind !== "object")
    return;
  const embeddedFields = type.properties.filter((p) => p.embedded);
  if (embeddedFields.length === 0)
    return;
  const ownNames = new Set([
    ...type.properties.filter((p) => !p.embedded).map((p) => p.name),
    ...type.methods.map((m) => m.name)
  ]);
  const promotedSources = new Map;
  for (const embedded of embeddedFields) {
    const embeddedType = env.lookupType(embedded.name);
    if (!embeddedType || embeddedType.kind !== "object") {
      addError(`Cannot embed '${embedded.name}': type not found`, decl.loc, `Make sure '${embedded.name}' is defined before '${decl.name}'`);
      continue;
    }
    for (const prop of embeddedType.properties) {
      if (ownNames.has(prop.name))
        continue;
      const sources = promotedSources.get(prop.name) || [];
      sources.push(embedded.name);
      promotedSources.set(prop.name, sources);
      if (sources.length === 1) {
        type.properties.push({
          ...prop,
          promotedFrom: embedded.name
        });
      }
    }
    for (const method of embeddedType.methods) {
      if (ownNames.has(method.name))
        continue;
      const sources = promotedSources.get(method.name) || [];
      sources.push(embedded.name);
      promotedSources.set(method.name, sources);
      if (sources.length === 1) {
        type.methods.push({
          ...method,
          promotedFrom: embedded.name
        });
      }
    }
  }
  for (const [name, sources] of promotedSources) {
    if (sources.length > 1) {
      addError(`Ambiguous access to '${name}' - exists in: ${sources.join(", ")}`, decl.loc, `Use explicit access: obj.TypeName.${name}`);
    }
  }
}
function collectFnDecl(decl, env, fnDecls, addError) {
  const fnType = fnDeclToType(decl);
  try {
    env.define(decl.name, fnType);
    fnDecls.set(decl.name, decl);
  } catch (e) {
    const err = TypeErrors.functionAlreadyDefined(decl.name);
    addError(err.message, decl.loc, err.hint);
  }
}

// src/types/passes/collect-declarations-pass.ts
class CollectDeclarationsPass {
  name = "collect-declarations";
  run(ctx) {
    const result = collectDeclarations({ program: ctx.program, env: ctx.env });
    ctx.env = result.env;
    ctx.fnDecls = result.fnDecls;
    ctx.errors.push(...result.errors);
  }
}

// src/types/passes/infer-types/context.ts
function createInferContext(env, fnDecls, dispatch) {
  return {
    env,
    errors: [],
    warnings: [],
    fnDecls,
    ...dispatch,
    currentFunction: null,
    inLoop: false,
    currentTypeName: null,
    unawaitedSpawns: new Map,
    lastSpawnInWithWasContextDependent: false,
    contextDependentSpawnsInWith: null,
    functionWithDepth: 0,
    withContextVars: new Set,
    withBlockDepth: 0,
    insideWithContext: false,
    needsContextCache: new Map
  };
}
function error(ctx, message, loc, hint) {
  ctx.errors.push(new TypeCheckError(message, loc, hint));
}
function warning(ctx, message) {
  ctx.warnings.push(message);
}
function recordType(ctx, node, type) {
  node.resolvedType = type;
}
function getExpectedType(node) {
  return node.expectedType;
}
function setExpectedType(node, type) {
  node.expectedType = type;
}

// src/types/passes/infer-types/check-pattern.ts
function resolve(type, ctx) {
  return type.kind === "ref" ? ctx.env.resolveType(type) : type;
}
function getLiteralType(value) {
  if (typeof value === "number")
    return Types.number;
  if (typeof value === "string")
    return Types.string;
  if (typeof value === "boolean")
    return Types.bool;
  if (value === null)
    return Types.null;
  return Types.unknown;
}
function canMatchLiteral(literalType, expectedType) {
  if (expectedType.kind === "unknown" || expectedType.kind === literalType.kind)
    return true;
  if (expectedType.kind === "union") {
    return expectedType.types.some((t) => canMatchLiteral(literalType, t));
  }
  if (expectedType.kind === "optional") {
    return literalType.kind === "null" || canMatchLiteral(literalType, expectedType.inner);
  }
  return false;
}
function isPatternTypeCompatible(patternType, expectedType, ctx) {
  if (expectedType.kind === "unknown")
    return true;
  if (isAssignable(patternType, expectedType, ctx.env))
    return true;
  if (expectedType.kind === "union") {
    return expectedType.types.some((t) => isAssignable(patternType, t, ctx.env));
  }
  if (expectedType.kind === "optional") {
    return isPatternTypeCompatible(patternType, expectedType.inner, ctx);
  }
  return false;
}
function isNumeric(type) {
  if (type.kind === "number" || type.kind === "unknown")
    return true;
  if (type.kind === "union")
    return type.types.some(isNumeric);
  if (type.kind === "optional")
    return isNumeric(type.inner);
  return false;
}
function checkPattern(ctx, pattern, expectedType) {
  const resolved = resolve(expectedType, ctx);
  switch (pattern.kind) {
    case "IdentifierPattern":
      ctx.env.define(pattern.name, expectedType);
      break;
    case "LiteralPattern": {
      if (!canMatchLiteral(getLiteralType(pattern.value), resolved)) {
        const err = TypeErrors.literalPatternMismatch(typeToString(getLiteralType(pattern.value)), typeToString(expectedType));
        error(ctx, err.message, pattern.loc, err.hint);
      }
      break;
    }
    case "ObjectPattern":
      handleObjectPattern(ctx, pattern, resolved, expectedType);
      break;
    case "ArrayPattern":
      handleArrayPattern(ctx, pattern, resolved, expectedType);
      break;
    case "RestPattern":
      if (resolved.kind === "list") {
        ctx.env.define(pattern.name, resolved);
      } else {
        const err = TypeErrors.patternTypeMismatch("rest", typeToString(expectedType));
        error(ctx, err.message, pattern.loc, err.hint);
        ctx.env.define(pattern.name, Types.list(Types.unknown));
      }
      break;
    case "TypePattern": {
      const patternType = astTypeToType(pattern.type);
      if (!isPatternTypeCompatible(patternType, expectedType, ctx)) {
        const err = TypeErrors.incompatibleTypePattern(typeToString(patternType), typeToString(expectedType));
        error(ctx, err.message, pattern.loc, err.hint);
      }
      if (pattern.binding)
        ctx.env.define(pattern.binding, patternType);
      break;
    }
    case "RangePattern":
      if (!isNumeric(resolved)) {
        const err = TypeErrors.rangePatternRequiresNumber(typeToString(expectedType));
        error(ctx, err.message, pattern.loc, err.hint);
      }
      break;
    case "WildcardPattern":
      break;
  }
}
function handleObjectPattern(ctx, pattern, resolved, expectedType) {
  if (resolved.kind === "map") {
    for (const prop of pattern.properties) {
      checkPattern(ctx, prop.pattern, resolved.valueType);
    }
    return;
  }
  if (resolved.kind !== "object" && resolved.kind !== "unknown") {
    const err = TypeErrors.patternTypeMismatch("object", typeToString(expectedType));
    error(ctx, err.message, pattern.loc, err.hint);
    for (const prop of pattern.properties)
      checkPattern(ctx, prop.pattern, Types.unknown);
    return;
  }
  if (resolved.kind === "unknown") {
    for (const prop of pattern.properties)
      checkPattern(ctx, prop.pattern, Types.unknown);
    return;
  }
  const objType = resolved;
  for (const prop of pattern.properties) {
    const propType = objType.properties.find((p) => p.name === prop.key);
    if (!propType) {
      const err = TypeErrors.unknownPatternProperty(prop.key, typeToString(expectedType));
      error(ctx, err.message, prop.pattern.loc ?? pattern.loc, err.hint);
      checkPattern(ctx, prop.pattern, Types.unknown);
    } else {
      checkPattern(ctx, prop.pattern, propType.type);
    }
  }
}
function handleArrayPattern(ctx, pattern, resolved, expectedType) {
  if (resolved.kind !== "list" && resolved.kind !== "tuple") {
    const err = TypeErrors.patternTypeMismatch("array", typeToString(expectedType));
    error(ctx, err.message, pattern.loc, err.hint);
    for (const el of pattern.elements)
      checkPattern(ctx, el, Types.unknown);
    return;
  }
  if (resolved.kind === "tuple") {
    const nonRest = pattern.elements.filter((e) => e.kind !== "RestPattern");
    const hasRest = pattern.elements.some((e) => e.kind === "RestPattern");
    if (!hasRest && nonRest.length !== resolved.elements.length || hasRest && nonRest.length > resolved.elements.length) {
      const err = TypeErrors.tuplePatternLengthMismatch(resolved.elements.length, nonRest.length);
      error(ctx, err.message, pattern.loc, err.hint);
    }
    let idx = 0;
    for (const el of pattern.elements) {
      if (el.kind === "RestPattern") {
        const rest = resolved.elements.slice(idx);
        ctx.env.define(el.name, rest.length > 0 ? Types.list(Types.union(...rest)) : Types.list(Types.unknown));
      } else {
        checkPattern(ctx, el, idx < resolved.elements.length ? resolved.elements[idx] : Types.unknown);
        idx++;
      }
    }
  } else {
    for (const el of pattern.elements) {
      if (el.kind === "RestPattern") {
        ctx.env.define(el.name, resolved);
      } else {
        checkPattern(ctx, el, resolved.elementType);
      }
    }
  }
}
function bindPattern(ctx, pattern, type, mutable = false) {
  const resolved = resolve(type, ctx);
  switch (pattern.kind) {
    case "IdentifierPattern":
      try {
        ctx.env.define(pattern.name, type, mutable);
      } catch {
        const err = TypeErrors.variableAlreadyDefined(pattern.name);
        error(ctx, err.message, pattern.loc, err.hint);
      }
      break;
    case "ObjectPattern":
      if (resolved.kind === "map") {
        for (const prop of pattern.properties)
          bindPattern(ctx, prop.pattern, resolved.valueType, mutable);
      } else if (resolved.kind === "object") {
        for (const prop of pattern.properties) {
          const propType = resolved.properties.find((p) => p.name === prop.key);
          if (!propType) {
            const err = TypeErrors.unknownPatternProperty(prop.key, typeToString(type));
            error(ctx, err.message, prop.pattern.loc ?? pattern.loc, err.hint);
            bindPattern(ctx, prop.pattern, Types.unknown, mutable);
          } else {
            bindPattern(ctx, prop.pattern, propType.type, mutable);
          }
        }
      } else if (resolved.kind === "unknown") {
        for (const prop of pattern.properties)
          bindPattern(ctx, prop.pattern, Types.unknown, mutable);
      } else {
        const err = TypeErrors.patternTypeMismatch("object", typeToString(type));
        error(ctx, err.message, pattern.loc, err.hint);
        for (const prop of pattern.properties)
          bindPattern(ctx, prop.pattern, Types.unknown, mutable);
      }
      break;
    case "ArrayPattern":
      if (resolved.kind === "list") {
        for (const el of pattern.elements) {
          if (el.kind === "RestPattern")
            ctx.env.define(el.name, resolved, mutable);
          else
            bindPattern(ctx, el, resolved.elementType, mutable);
        }
      } else if (resolved.kind === "tuple") {
        let idx = 0;
        for (const el of pattern.elements) {
          if (el.kind === "RestPattern") {
            const rest = resolved.elements.slice(idx);
            ctx.env.define(el.name, Types.list(rest.length > 0 ? Types.union(...rest) : Types.unknown), mutable);
          } else {
            bindPattern(ctx, el, idx < resolved.elements.length ? resolved.elements[idx] : Types.unknown, mutable);
            idx++;
          }
        }
      } else {
        const err = TypeErrors.patternTypeMismatch("array", typeToString(type));
        error(ctx, err.message, pattern.loc, err.hint);
        for (const el of pattern.elements)
          bindPattern(ctx, el, Types.unknown, mutable);
      }
      break;
    case "RestPattern":
      if (resolved.kind === "list")
        ctx.env.define(pattern.name, resolved, mutable);
      else {
        const err = TypeErrors.patternTypeMismatch("rest", typeToString(type));
        error(ctx, err.message, pattern.loc, err.hint);
        ctx.env.define(pattern.name, Types.list(Types.unknown), mutable);
      }
      break;
  }
}

// src/types/passes/context-analysis.ts
function fnNeedsContext(name, env, fnDecls, cache) {
  if (cache.has(name))
    return cache.get(name);
  cache.set(name, false);
  const symbol = env.lookup(name);
  if (symbol?.type.kind === "function" && symbol.type.context.length > 0) {
    cache.set(name, true);
    return true;
  }
  const decl = fnDecls.get(name);
  if (decl?.body && blockNeedsContext(decl.body, env, fnDecls, cache)) {
    cache.set(name, true);
    return true;
  }
  return false;
}
function blockNeedsContext(block, env, fnDecls, cache) {
  return block.statements.some((s) => stmtNeedsContext(s, env, fnDecls, cache));
}
function stmtNeedsContext(stmt, env, fnDecls, cache) {
  switch (stmt.kind) {
    case "ExprStmt":
      return exprNeedsContext(stmt.expr, env, fnDecls, cache);
    case "LetStmt":
    case "VarStmt":
      return exprNeedsContext(stmt.value, env, fnDecls, cache);
    case "AssignStmt":
      return exprNeedsContext(stmt.value, env, fnDecls, cache);
    case "IfStmt": {
      const then = stmt.then.kind === "Block" ? blockNeedsContext(stmt.then, env, fnDecls, cache) : stmtNeedsContext(stmt.then, env, fnDecls, cache);
      return exprNeedsContext(stmt.condition, env, fnDecls, cache) || then || (stmt.else ? blockNeedsContext(stmt.else, env, fnDecls, cache) : false);
    }
    case "ForStmt":
      return (stmt.iterable ? exprNeedsContext(stmt.iterable, env, fnDecls, cache) : false) || blockNeedsContext(stmt.body, env, fnDecls, cache);
    case "ReturnStmt":
      return stmt.value ? exprNeedsContext(stmt.value, env, fnDecls, cache) : false;
    case "WithStmt":
      return blockNeedsContext(stmt.body, env, fnDecls, cache);
    default:
      return false;
  }
}
function exprNeedsContext(expr, env, fnDecls, cache) {
  switch (expr.kind) {
    case "CallExpr":
      if (expr.callee.kind === "Identifier" && fnNeedsContext(expr.callee.name, env, fnDecls, cache))
        return true;
      return expr.args.some((a) => exprNeedsContext("kind" in a ? a : a.value, env, fnDecls, cache));
    case "LambdaExpr":
      return expr.body.kind === "Block" ? blockNeedsContext(expr.body, env, fnDecls, cache) : exprNeedsContext(expr.body, env, fnDecls, cache);
    case "BinaryExpr":
      return exprNeedsContext(expr.left, env, fnDecls, cache) || exprNeedsContext(expr.right, env, fnDecls, cache);
    case "UnaryExpr":
      return exprNeedsContext(expr.operand, env, fnDecls, cache);
    case "IfExpr":
      return exprNeedsContext(expr.condition, env, fnDecls, cache) || exprNeedsContext(expr.then, env, fnDecls, cache) || exprNeedsContext(expr.else, env, fnDecls, cache);
    case "ListExpr":
      return expr.elements.some((e) => exprNeedsContext(e.kind === "SpreadElement" ? e.expr : e, env, fnDecls, cache));
    case "SetExpr":
      return expr.elements.some((e) => exprNeedsContext(e, env, fnDecls, cache));
    case "MapExpr":
      return expr.entries.some((e) => exprNeedsContext(e.value, env, fnDecls, cache));
    case "MemberExpr":
      return exprNeedsContext(expr.object, env, fnDecls, cache);
    case "IndexExpr":
      return exprNeedsContext(expr.object, env, fnDecls, cache) || exprNeedsContext(expr.index, env, fnDecls, cache);
    case "PipeExpr":
      return exprNeedsContext(expr.left, env, fnDecls, cache) || exprNeedsContext(expr.right, env, fnDecls, cache);
    default:
      return false;
  }
}
function exprContainsEscapingLambda(expr, ctxVars, env, fnDecls, cache) {
  switch (expr.kind) {
    case "LambdaExpr":
      return expr.body.kind === "Block" ? blockNeedsContext(expr.body, env, fnDecls, cache) : exprNeedsContext(expr.body, env, fnDecls, cache);
    case "Identifier":
      return ctxVars.has(expr.name);
    case "ListExpr":
      return expr.elements.some((e) => exprContainsEscapingLambda(e.kind === "SpreadElement" ? e.expr : e, ctxVars, env, fnDecls, cache));
    case "SetExpr":
      return expr.elements.some((e) => exprContainsEscapingLambda(e, ctxVars, env, fnDecls, cache));
    case "MapExpr":
      return expr.entries.some((e) => exprContainsEscapingLambda(e.value, ctxVars, env, fnDecls, cache));
    case "IfExpr":
      return exprContainsEscapingLambda(expr.then, ctxVars, env, fnDecls, cache) || exprContainsEscapingLambda(expr.else, ctxVars, env, fnDecls, cache);
    case "CallExpr":
      return expr.args.some((a) => exprContainsEscapingLambda("kind" in a ? a : a.value, ctxVars, env, fnDecls, cache));
    default:
      return false;
  }
}

// src/types/passes/infer-types/infer-spawn.ts
function inferSpawnExpr(ctx, expr) {
  ctx.lastSpawnInWithWasContextDependent = false;
  if (ctx.functionWithDepth > 0) {
    const capturesContext = exprContainsEscapingLambda(expr.expr, ctx.withContextVars, ctx.env, ctx.fnDecls, ctx.needsContextCache) || exprNeedsContext(expr.expr, ctx.env, ctx.fnDecls, ctx.needsContextCache);
    if (capturesContext)
      ctx.lastSpawnInWithWasContextDependent = true;
  }
  const innerType = ctx.inferExpr(ctx, expr.expr);
  return Types.promise(innerType.kind === "function" ? innerType.returnType : innerType);
}
function consumeSpawnsInExpr(ctx, expr) {
  switch (expr.kind) {
    case "Identifier":
      ctx.unawaitedSpawns.delete(expr.name);
      ctx.contextDependentSpawnsInWith?.delete(expr.name);
      break;
    case "ListExpr":
      for (const el of expr.elements) {
        if (el.kind !== "SpreadElement")
          consumeSpawnsInExpr(ctx, el);
        else
          consumeSpawnsInExpr(ctx, el.expr);
      }
      break;
    case "SetExpr":
      for (const el of expr.elements)
        consumeSpawnsInExpr(ctx, el);
      break;
    case "MapExpr":
      for (const entry of expr.entries)
        consumeSpawnsInExpr(ctx, entry.value);
      break;
    case "IfExpr":
      consumeSpawnsInExpr(ctx, expr.then);
      if (expr.else)
        consumeSpawnsInExpr(ctx, expr.else);
      break;
    case "IndexExpr":
      consumeSpawnsInExpr(ctx, expr.object);
      break;
    case "MemberExpr":
      consumeSpawnsInExpr(ctx, expr.object);
      break;
    case "CallExpr": {
      const callReturnType = expr.resolvedType ?? Types.unknown;
      const isValuesCall = expr.callee.kind === "Identifier" && expr.callee.name === "values";
      if (typeInvolvesPromise(callReturnType, ctx.env) || isValuesCall) {
        for (const arg of expr.args)
          consumeSpawnsInExpr(ctx, "kind" in arg ? arg : arg.value);
      }
      break;
    }
  }
}
function exprContainsSpawn(ctx, expr) {
  if (expr.kind === "SpawnExpr")
    return true;
  if (expr.kind === "Identifier" && ctx.unawaitedSpawns.has(expr.name))
    return true;
  if (expr.kind === "CallExpr") {
    for (const arg of expr.args) {
      if (exprContainsSpawn(ctx, "kind" in arg ? arg : arg.value))
        return true;
    }
  }
  if (expr.kind === "ListExpr") {
    for (const el of expr.elements) {
      if (el.kind === "SpreadElement" ? exprContainsSpawn(ctx, el.expr) : exprContainsSpawn(ctx, el))
        return true;
    }
  }
  if (expr.kind === "SetExpr") {
    for (const el of expr.elements)
      if (exprContainsSpawn(ctx, el))
        return true;
  }
  if (expr.kind === "MapExpr") {
    for (const entry of expr.entries)
      if (exprContainsSpawn(ctx, entry.value))
        return true;
  }
  if (expr.kind === "IndexExpr" && expr.object.kind === "Identifier" && ctx.unawaitedSpawns.has(expr.object.name))
    return true;
  if (expr.kind === "MemberExpr" && expr.object.kind === "Identifier" && ctx.unawaitedSpawns.has(expr.object.name))
    return true;
  if (expr.kind === "IfExpr") {
    if (exprContainsSpawn(ctx, expr.then))
      return true;
    if (expr.else && exprContainsSpawn(ctx, expr.else))
      return true;
  }
  return false;
}
function transferSpawnTracking(ctx, expr) {
  if (expr.kind === "Identifier") {
    ctx.unawaitedSpawns.delete(expr.name);
  } else if (expr.kind === "IfExpr") {
    if (expr.then.kind === "Identifier")
      ctx.unawaitedSpawns.delete(expr.then.name);
    if (expr.else?.kind === "Identifier")
      ctx.unawaitedSpawns.delete(expr.else.name);
  } else if (expr.kind === "ListExpr") {
    for (const el of expr.elements) {
      if (el.kind === "Identifier")
        ctx.unawaitedSpawns.delete(el.name);
      else if (el.kind === "SpreadElement" && el.expr.kind === "Identifier")
        ctx.unawaitedSpawns.delete(el.expr.name);
    }
  } else if (expr.kind === "SetExpr") {
    for (const el of expr.elements)
      if (el.kind === "Identifier")
        ctx.unawaitedSpawns.delete(el.name);
  } else if (expr.kind === "MapExpr") {
    for (const entry of expr.entries)
      if (entry.value.kind === "Identifier")
        ctx.unawaitedSpawns.delete(entry.value.name);
  } else if (expr.kind === "CallExpr") {
    for (const arg of expr.args)
      transferSpawnTracking(ctx, "kind" in arg ? arg : arg.value);
  }
}

// src/types/passes/infer-types/check-control-flow.ts
function checkIfStmt(ctx, stmt) {
  ctx.inferExpr(ctx, stmt.condition);
  const narrowedEnv = ctx.env.child();
  applyTypeNarrowing(ctx, stmt.condition, narrowedEnv, true);
  if (stmt.then.kind === "Block") {
    const savedEnv = ctx.env;
    ctx.env = narrowedEnv;
    for (const s of stmt.then.statements)
      ctx.checkStatement(ctx, s);
    ctx.env = savedEnv;
  } else {
    const savedEnv = ctx.env;
    ctx.env = narrowedEnv;
    ctx.checkStatement(ctx, stmt.then);
    ctx.env = savedEnv;
  }
  for (const elif of stmt.elseIfs) {
    ctx.inferExpr(ctx, elif.condition);
    const elifEnv = ctx.env.child();
    applyTypeNarrowing(ctx, elif.condition, elifEnv, true);
    const savedEnv = ctx.env;
    ctx.env = elifEnv;
    for (const s of elif.body.statements)
      ctx.checkStatement(ctx, s);
    ctx.env = savedEnv;
  }
  if (stmt.else) {
    const elseEnv = ctx.env.child();
    applyTypeNarrowing(ctx, stmt.condition, elseEnv, false);
    const savedEnv = ctx.env;
    ctx.env = elseEnv;
    for (const s of stmt.else.statements)
      ctx.checkStatement(ctx, s);
    ctx.env = savedEnv;
  }
  if (stmt.pattern && stmt.elseReturn)
    ctx.inferExpr(ctx, stmt.elseReturn);
}
function applyTypeNarrowing(ctx, condition, env, truthyBranch) {
  if (condition.kind === "BinaryExpr" && condition.op === "is") {
    if (condition.left.kind === "Identifier" && condition.right.kind === "Identifier") {
      const varName = condition.left.name;
      const typeName = condition.right.name;
      const symbol = ctx.env.lookup(varName);
      if (symbol) {
        if (truthyBranch) {
          env.define(varName, ctx.env.lookupType(typeName) ?? Types.ref(typeName), symbol.mutable);
        } else if (symbol.type.kind === "union") {
          const remaining = symbol.type.types.filter((t) => {
            if (t.kind === "ref")
              return t.name !== typeName;
            if (t.kind === "object")
              return t.name !== typeName;
            return typeToString(t) !== typeName;
          });
          if (remaining.length === 1)
            env.define(varName, remaining[0], symbol.mutable);
          else if (remaining.length > 1)
            env.define(varName, Types.union(...remaining), symbol.mutable);
        }
      }
    }
  } else if (condition.kind === "BinaryExpr" && (condition.op === "!=" || condition.op === "==") && condition.left.kind === "Identifier" && condition.right.kind === "Literal" && condition.right.value === null) {
    const varName = condition.left.name;
    const symbol = ctx.env.lookup(varName);
    if (symbol && isNullable(symbol.type)) {
      const isNotNull = condition.op === "!=" && truthyBranch || condition.op === "==" && !truthyBranch;
      if (isNotNull)
        env.define(varName, nonNull(symbol.type), symbol.mutable);
    }
  } else if (condition.kind === "BinaryExpr" && (condition.op === "==" || condition.op === "!=") && condition.left.kind === "Identifier" && condition.right.kind === "Literal") {
    const varName = condition.left.name;
    const symbol = ctx.env.lookup(varName);
    if (symbol) {
      const isEqual = condition.op === "==" && truthyBranch || condition.op === "!=" && !truthyBranch;
      if (isEqual) {
        env.define(varName, Types.literal(condition.right.value), symbol.mutable);
      } else if (symbol.type.kind === "union") {
        const literalStr = JSON.stringify(condition.right.value);
        const remaining = symbol.type.types.filter((t) => {
          if (t.kind === "literal")
            return JSON.stringify(t.value) !== literalStr;
          return true;
        });
        if (remaining.length === 1)
          env.define(varName, remaining[0], symbol.mutable);
        else if (remaining.length > 1)
          env.define(varName, Types.union(...remaining), symbol.mutable);
      }
    }
  } else if (condition.kind === "BinaryExpr" && (condition.op === "==" || condition.op === "!=") && condition.left.kind === "MemberExpr" && condition.right.kind === "Literal") {
    const memberExpr = condition.left;
    if (memberExpr.object.kind === "Identifier") {
      const varName = memberExpr.object.name;
      const propName = memberExpr.property;
      const symbol = ctx.env.lookup(varName);
      if (symbol && symbol.type.kind === "union") {
        const isEqual = condition.op === "==" && truthyBranch || condition.op === "!=" && !truthyBranch;
        const literalValue = condition.right.value;
        const matching = [];
        const nonMatching = [];
        for (const t of symbol.type.types) {
          const resolved = t.kind === "ref" ? ctx.env.resolveType(t) : t;
          if (resolved.kind === "object") {
            const prop = resolved.properties.find((p) => p.name === propName);
            if (prop && prop.type.kind === "literal" && prop.type.value === literalValue)
              matching.push(t);
            else
              nonMatching.push(t);
          } else
            nonMatching.push(t);
        }
        if (isEqual && matching.length > 0) {
          if (matching.length === 1)
            env.define(varName, matching[0], symbol.mutable);
          else
            env.define(varName, Types.union(...matching), symbol.mutable);
        } else if (!isEqual && nonMatching.length > 0) {
          if (nonMatching.length === 1)
            env.define(varName, nonMatching[0], symbol.mutable);
          else
            env.define(varName, Types.union(...nonMatching), symbol.mutable);
        }
      }
    }
  } else if (condition.kind === "BinaryExpr" && condition.op === "and") {
    applyTypeNarrowing(ctx, condition.left, env, truthyBranch);
    applyTypeNarrowing(ctx, condition.right, env, truthyBranch);
  } else if (condition.kind === "BinaryExpr" && (condition.op === "==" || condition.op === "!=") && condition.left.kind === "CallExpr") {
    const call = condition.left;
    const callee = call.callee;
    const typeStr = condition.right.kind === "Literal" && typeof condition.right.value === "string" ? condition.right.value : null;
    if (callee.kind === "Identifier" && callee.name === "typeof" && call.args.length === 1 && typeStr) {
      const raw = call.args[0];
      const argExpr = raw && "value" in raw ? raw.value : raw;
      if (argExpr?.kind === "Identifier") {
        const varName = argExpr.name;
        const symbol = ctx.env.lookup(varName);
        if (symbol) {
          let narrowedType = null;
          if (typeStr === "number")
            narrowedType = Types.number;
          else if (typeStr === "string")
            narrowedType = Types.string;
          else if (typeStr === "boolean")
            narrowedType = Types.bool;
          else if (typeStr === "null")
            narrowedType = Types.null;
          if (narrowedType) {
            const isEqual = condition.op === "==" && truthyBranch || condition.op === "!=" && !truthyBranch;
            if (isEqual)
              env.define(varName, narrowedType, symbol.mutable);
          }
        }
      }
    }
  } else if (condition.kind === "UnaryExpr" && (condition.op === "not" || condition.op === "!")) {
    applyTypeNarrowing(ctx, condition.operand, env, !truthyBranch);
  }
}
function checkForStmt(ctx, stmt) {
  const prevInLoop = ctx.inLoop;
  ctx.inLoop = true;
  const bodyEnv = ctx.env.child();
  if (stmt.pattern && stmt.iterable) {
    const iterableType = ctx.inferExpr(ctx, stmt.iterable);
    if (!isIterable(iterableType)) {
      const err = TypeErrors.nonIterableForLoop(typeToString(iterableType));
      error(ctx, err.message, stmt.iterable.loc, err.hint);
    }
    const elementType = getIterableElementType(iterableType);
    const savedEnv2 = ctx.env;
    ctx.env = bodyEnv;
    bindPattern(ctx, stmt.pattern, elementType, false);
    ctx.env = savedEnv2;
  }
  const savedEnv = ctx.env;
  ctx.env = bodyEnv;
  ctx.checkBlock(ctx, stmt.body);
  ctx.env = savedEnv;
  ctx.inLoop = prevInLoop;
}
function checkMatchStmt(ctx, stmt) {
  const valueType = ctx.inferExpr(ctx, stmt.value);
  for (const arm of stmt.arms) {
    const armEnv = ctx.env.child();
    const savedEnv = ctx.env;
    ctx.env = armEnv;
    checkPattern(ctx, arm.pattern, valueType);
    if (arm.guard) {
      const guardType = ctx.inferExpr(ctx, arm.guard);
      if (guardType.kind !== "bool") {
        const err = TypeErrors.guardMustBeBool(typeToString(guardType));
        error(ctx, err.message, arm.guard.loc, err.hint);
      }
    }
    if (arm.body.kind === "Block")
      ctx.checkBlock(ctx, arm.body);
    else
      ctx.inferExpr(ctx, arm.body);
    ctx.env = savedEnv;
  }
  checkMatchExhaustiveness(ctx, valueType, stmt.arms, stmt.loc);
}
function checkMatchExhaustiveness(ctx, valueType, arms, loc) {
  const hasCatchAll = arms.some((arm) => arm.pattern.kind === "WildcardPattern" || arm.pattern.kind === "IdentifierPattern" && !arm.guard);
  if (hasCatchAll)
    return;
  if (valueType.kind === "union") {
    const coveredTypes = new Set;
    for (const arm of arms) {
      if (arm.guard)
        continue;
      if (arm.pattern.kind === "TypePattern") {
        coveredTypes.add(arm.pattern.type.kind === "NamedType" ? arm.pattern.type.name : typeToString(astTypeToType(arm.pattern.type)));
      } else if (arm.pattern.kind === "LiteralPattern" && arm.pattern.value === null) {
        coveredTypes.add("null");
      }
    }
    const uncovered = [];
    for (const t of valueType.types) {
      const typeName = t.kind === "ref" ? t.name : t.kind === "object" && t.name ? t.name : typeToString(t);
      if (!coveredTypes.has(typeName))
        uncovered.push(typeName);
    }
    if (uncovered.length > 0) {
      const err = TypeErrors.matchNotExhaustive(uncovered);
      error(ctx, err.message, loc, err.hint);
    }
  }
  if (valueType.kind === "optional") {
    const hasNullCase = arms.some((arm) => arm.pattern.kind === "LiteralPattern" && arm.pattern.value === null);
    const hasValueCase = arms.some((arm) => arm.pattern.kind === "TypePattern" || arm.pattern.kind === "IdentifierPattern");
    const missing = [];
    if (!hasNullCase)
      missing.push("null");
    if (!hasValueCase)
      missing.push(typeToString(valueType.inner));
    if (missing.length > 0) {
      const err = TypeErrors.matchNotExhaustive(missing);
      error(ctx, err.message, loc, err.hint);
    }
  }
  if (valueType.kind === "bool") {
    const hasTrue = arms.some((arm) => arm.pattern.kind === "LiteralPattern" && arm.pattern.value === true);
    const hasFalse = arms.some((arm) => arm.pattern.kind === "LiteralPattern" && arm.pattern.value === false);
    const missing = [];
    if (!hasTrue)
      missing.push("true");
    if (!hasFalse)
      missing.push("false");
    if (missing.length > 0) {
      const err = TypeErrors.matchNotExhaustive(missing);
      error(ctx, err.message, loc, err.hint);
    }
  }
}
function checkReturnStmt(ctx, stmt) {
  if (!ctx.currentFunction) {
    const err = TypeErrors.returnOutsideFunction();
    error(ctx, err.message, stmt.loc, err.hint);
    return;
  }
  if (stmt.value) {
    setExpectedType(stmt.value, ctx.currentFunction.returnType);
    const returnType = ctx.inferExpr(ctx, stmt.value);
    if (!isAssignable(returnType, ctx.currentFunction.returnType, ctx.env)) {
      const err = TypeErrors.typeMismatch(typeToString(ctx.currentFunction.returnType), typeToString(returnType));
      error(ctx, err.message, stmt.loc, err.hint);
    }
    consumeSpawnsInExpr(ctx, stmt.value);
    if (ctx.functionWithDepth > 0 && exprContainsEscapingLambda(stmt.value, ctx.withContextVars, ctx.env, ctx.fnDecls, ctx.needsContextCache)) {
      error(ctx, `Cannot return closure that depends on context from 'with' block - it would outlive the context scope`, stmt.loc, `Context is cleaned up when 'with' block exits, but the returned closure needs it to execute`);
    }
  } else if (ctx.currentFunction.returnType.kind !== "void") {
    const err = TypeErrors.returnMissingValue(typeToString(ctx.currentFunction.returnType));
    error(ctx, err.message, stmt.loc, err.hint);
  }
}
function checkYieldStmt(ctx, stmt) {
  if (!ctx.currentFunction || !ctx.currentFunction.isGenerator) {
    const err = TypeErrors.yieldOutsideGenerator();
    error(ctx, err.message, stmt.loc, err.hint);
    return;
  }
  setExpectedType(stmt.value, ctx.currentFunction.returnType);
  ctx.inferExpr(ctx, stmt.value);
}
function checkTryStmt(ctx, stmt) {
  ctx.checkBlock(ctx, stmt.body);
  if (stmt.catch) {
    const catchEnv = ctx.env.child();
    catchEnv.define(stmt.catch.name, Types.ref("Error"));
    const savedEnv = ctx.env;
    ctx.env = catchEnv;
    ctx.checkBlock(ctx, stmt.catch.body);
    ctx.env = savedEnv;
  }
}
function checkWithStmt(ctx, stmt) {
  const bindings = [];
  const isFunctionLevel = ctx.currentFunction !== null;
  const savedWithContextVars = new Set(ctx.withContextVars);
  const closableType = ctx.env.lookupType("Closable") ?? null;
  if (!closableType) {
    error(ctx, "Closable interface not found (builtins required)", stmt.loc);
    return;
  }
  for (const ctxBinding of stmt.contexts) {
    const ctxType = ctx.inferExpr(ctx, ctxBinding.expr);
    if (!isAssignable(ctxType, closableType, ctx.env)) {
      error(ctx, `Expression in 'with' must satisfy Closable (must have close(): void)`, ctxBinding.expr.loc, `Type '${typeToString(ctxType)}' does not have close(): void`);
    }
    if (ctxBinding.name) {
      bindings.push({ name: ctxBinding.name, type: ctxType });
      if (isFunctionLevel)
        ctx.withContextVars.add(ctxBinding.name);
    }
  }
  const withEnv = ctx.env.withContext(bindings);
  const savedEnv = ctx.env;
  ctx.env = withEnv;
  ctx.withBlockDepth++;
  ctx.insideWithContext = true;
  let savedContextDependent = null;
  if (isFunctionLevel) {
    ctx.functionWithDepth++;
    savedContextDependent = ctx.contextDependentSpawnsInWith;
    ctx.contextDependentSpawnsInWith = new Set;
  }
  ctx.checkBlock(ctx, stmt.body);
  if (isFunctionLevel) {
    const lastStmt = stmt.body.statements[stmt.body.statements.length - 1];
    if (lastStmt?.kind === "ExprStmt" && exprContainsEscapingLambda(lastStmt.expr, ctx.withContextVars, ctx.env, ctx.fnDecls, ctx.needsContextCache)) {
      error(ctx, `Cannot return closure that depends on context from 'with' block - it would outlive the context scope`, lastStmt.loc, `Context is cleaned up when 'with' block exits, but the returned closure needs it to execute`);
    }
    for (const name of ctx.contextDependentSpawnsInWith) {
      const loc = ctx.unawaitedSpawns.get(name);
      if (loc) {
        error(ctx, `Cannot use 'spawn' inside function-level 'with' block - spawned task may outlive context scope`, loc, `Add e.g. \`let _ = race([${name}])\` or \`all_settled([${name}])\` before the block ends, or spawn a task that does not use the context`);
        ctx.unawaitedSpawns.delete(name);
      }
    }
    ctx.contextDependentSpawnsInWith = savedContextDependent;
    ctx.functionWithDepth--;
  }
  ctx.env = savedEnv;
  ctx.withBlockDepth--;
  ctx.insideWithContext = ctx.withBlockDepth > 0;
  ctx.withContextVars = savedWithContextVars;
}

// src/types/passes/infer-types/check-declarations.ts
function checkFnDecl(ctx, decl) {
  const fnType = fnDeclToType(decl);
  const fnEnv = ctx.env.child();
  if (fnType.typeParams?.length) {
    for (const tp of fnType.typeParams)
      fnEnv.bindTypeParam(tp.name, Types.typevar(tp.name));
  }
  for (const param of decl.params) {
    fnEnv.define(param.name, param.type ? astTypeToType(param.type) : Types.unknown);
  }
  if (decl.using) {
    validateUsingClause(ctx, decl.using);
    for (const binding of decl.using.bindings) {
      if (binding.name)
        fnEnv.define(binding.name, astTypeToType(binding.type));
    }
  }
  const savedEnv = ctx.env;
  const savedFn = ctx.currentFunction;
  const savedSpawns = ctx.unawaitedSpawns;
  ctx.unawaitedSpawns = new Map;
  ctx.env = fnEnv;
  ctx.currentFunction = fnType;
  const bodyEnv = ctx.env.child();
  ctx.env = bodyEnv;
  for (const stmt of decl.body.statements)
    ctx.checkStatement(ctx, stmt);
  const lastStmt = decl.body.statements[decl.body.statements.length - 1];
  if (lastStmt?.kind === "ExprStmt") {
    consumeSpawnsInExpr(ctx, lastStmt.expr);
    if (ctx.functionWithDepth > 0 && exprContainsEscapingLambda(lastStmt.expr, ctx.withContextVars, ctx.env, ctx.fnDecls, ctx.needsContextCache)) {
      error(ctx, `Cannot return closure that depends on context from 'with' block - it would outlive the context scope`, lastStmt.loc, `Context is cleaned up when 'with' block exits, but the returned closure needs it to execute`);
    }
    if (decl.returnType && fnType.returnType.kind !== "promise" && fnType.returnType.kind !== "unknown") {
      const implicitReturnType = lastStmt.expr.resolvedType ?? Types.unknown;
      const declaredReturnType = fnType.returnType;
      const resolved = implicitReturnType.kind === "promise" ? implicitReturnType.resolveType : implicitReturnType;
      if (!isAssignable(resolved, declaredReturnType, ctx.env)) {
        const err = TypeErrors.typeMismatch(typeToString(declaredReturnType), typeToString(resolved));
        error(ctx, err.message, lastStmt.loc, err.hint);
      }
    }
  }
  for (const [name, loc] of ctx.unawaitedSpawns) {
    error(ctx, `spawn result '${name}' is never awaited (pass to race() or all() before function returns)`, loc);
  }
  ctx.unawaitedSpawns = savedSpawns;
  ctx.env = savedEnv;
  ctx.currentFunction = savedFn;
  recordType(ctx, decl, fnType);
}
function checkObjectTypeBody(ctx, typeName, body, objType, opts) {
  if (!opts.isExtern) {
    for (const member of body.members) {
      if (member.kind === "MethodDecl" && !member.body) {
        const err = TypeErrors.methodRequiresBody(member.name, typeName);
        error(ctx, err.message, member.loc, err.hint);
      }
    }
  }
  const savedTypeName = ctx.currentTypeName;
  ctx.currentTypeName = typeName;
  const typeEnv = ctx.env.child();
  for (const prop of objType.properties)
    typeEnv.define(prop.name, prop.type, true);
  for (const member of body.members) {
    if (member.kind === "FieldDecl" && member.defaultValue) {
      const savedEnv = ctx.env;
      ctx.env = typeEnv;
      const declaredType = member.type ? astTypeToType(member.type) : undefined;
      if (declaredType)
        setExpectedType(member.defaultValue, declaredType);
      const valueType = ctx.inferExpr(ctx, member.defaultValue);
      if (!member.type && member.computed) {
        const prop = objType.properties.find((p) => p.name === member.name);
        if (prop)
          prop.type = valueType;
      }
      ctx.env = savedEnv;
      if (member.type) {
        const expectedType = astTypeToType(member.type);
        if (!isAssignable(valueType, expectedType, ctx.env)) {
          const err = TypeErrors.typeMismatch(typeToString(expectedType), typeToString(valueType));
          error(ctx, err.message, member.loc, err.hint);
        }
      }
    }
  }
  for (const member of body.members) {
    if (member.kind === "MethodDecl" && member.body)
      checkMethodBody(ctx, member, objType);
  }
  ctx.currentTypeName = savedTypeName;
}
function checkTypeDecl(ctx, decl) {
  const typeObj = ctx.env.lookupType(decl.name);
  if (!typeObj || typeObj.kind !== "object")
    return;
  checkObjectTypeBody(ctx, decl.name, decl.body, typeObj, {
    isExtern: !!decl.isExtern
  });
}
function checkMethodBody(ctx, method, typeObj) {
  const typeFieldsEnv = ctx.env.child();
  for (const prop of typeObj.properties)
    typeFieldsEnv.define(prop.name, prop.type, true);
  for (const m of typeObj.methods)
    typeFieldsEnv.define(m.name, m.type);
  const methodEnv = typeFieldsEnv.child();
  for (const param of method.params)
    methodEnv.define(param.name, param.type ? astTypeToType(param.type) : Types.unknown);
  const methodType = typeObj.methods.find((m) => m.name === method.name);
  const fnType = methodType?.type || Types.fn([], Types.unknown);
  const savedEnv = ctx.env;
  const savedFn = ctx.currentFunction;
  const savedSpawns = ctx.unawaitedSpawns;
  ctx.unawaitedSpawns = new Map;
  ctx.env = methodEnv;
  ctx.currentFunction = fnType;
  for (const stmt of method.body.statements)
    ctx.checkStatement(ctx, stmt);
  const lastStmt = method.body.statements[method.body.statements.length - 1];
  if (lastStmt?.kind === "ExprStmt" && method.returnType) {
    const implicitReturnType = lastStmt.expr.resolvedType ?? Types.unknown;
    if (!isAssignable(implicitReturnType, fnType.returnType, ctx.env)) {
      const err = TypeErrors.typeMismatch(typeToString(fnType.returnType), typeToString(implicitReturnType));
      error(ctx, err.message, lastStmt.loc, err.hint);
    }
  }
  for (const [name, loc] of ctx.unawaitedSpawns) {
    error(ctx, `spawn result '${name}' is never awaited (pass to race() or all() before method returns)`, loc);
  }
  ctx.unawaitedSpawns = savedSpawns;
  ctx.env = savedEnv;
  ctx.currentFunction = savedFn;
}
function validateUsingClause(ctx, using) {
  const closableType = ctx.env.lookupType("Closable") ?? null;
  if (!closableType) {
    error(ctx, "Closable interface not found (builtins required)", using.loc);
    return;
  }
  for (const binding of using.bindings) {
    const bindingType = astTypeToType(binding.type);
    if (!isAssignable(bindingType, closableType, ctx.env)) {
      const typeName = binding.type.kind === "NamedType" ? binding.type.name : "unknown";
      error(ctx, `Type '${typeName}' used in 'using' clause must satisfy Closable (must have close(): void)`, binding.loc, `Ensure the type has a close(): void method`);
    }
  }
}
function checkTestDecl(ctx, decl) {
  const testEnv = ctx.env.child();
  const savedEnv = ctx.env;
  ctx.env = testEnv;
  ctx.checkBlock(ctx, decl.body);
  ctx.env = savedEnv;
}

// src/types/passes/infer-types/check-stmt.ts
function checkStatement(ctx, stmt) {
  switch (stmt.kind) {
    case "LetStmt":
      checkLetStmt(ctx, stmt);
      break;
    case "VarStmt":
      checkVarStmt(ctx, stmt);
      break;
    case "AssignStmt":
      checkAssignStmt(ctx, stmt);
      break;
    case "IfStmt":
      checkIfStmt(ctx, stmt);
      break;
    case "ForStmt":
      checkForStmt(ctx, stmt);
      break;
    case "MatchStmt":
      checkMatchStmt(ctx, stmt);
      break;
    case "ReturnStmt":
      checkReturnStmt(ctx, stmt);
      break;
    case "YieldStmt":
      checkYieldStmt(ctx, stmt);
      break;
    case "BreakStmt":
    case "ContinueStmt":
      if (!ctx.inLoop) {
        const err = stmt.kind === "BreakStmt" ? TypeErrors.breakOutsideLoop() : TypeErrors.continueOutsideLoop();
        error(ctx, err.message, stmt.loc, err.hint);
      }
      break;
    case "DeferStmt":
      checkStatement(ctx, stmt.body);
      break;
    case "TryStmt":
      checkTryStmt(ctx, stmt);
      break;
    case "ThrowStmt":
      ctx.inferExpr(ctx, stmt.value);
      break;
    case "WithStmt":
      checkWithStmt(ctx, stmt);
      break;
    case "ExprStmt":
      if (stmt.expr.kind === "SpawnExpr")
        error(ctx, "spawn result must be used (await, pass to all(), or assign to variable)", stmt.expr.loc);
      ctx.inferExpr(ctx, stmt.expr);
      break;
    case "FnDecl":
      checkFnDecl(ctx, stmt);
      break;
    case "ExternFnDecl":
    case "InterfaceDecl":
    case "ImportDecl":
      break;
    case "TypeDecl":
      checkTypeDecl(ctx, stmt);
      break;
    case "TestDecl":
      checkTestDecl(ctx, stmt);
      break;
  }
}
function checkLetStmt(ctx, stmt) {
  const declaredType = stmt.type ? astTypeToType(stmt.type) : undefined;
  if (declaredType)
    setExpectedType(stmt.value, declaredType);
  const valueType = ctx.inferExpr(ctx, stmt.value);
  const resolvedDeclared = declaredType ?? valueType;
  if (stmt.type && !isAssignable(valueType, resolvedDeclared, ctx.env)) {
    const err = TypeErrors.typeMismatch(typeToString(resolvedDeclared), typeToString(valueType));
    error(ctx, err.message, stmt.loc, err.hint);
  }
  if (stmt.pattern.kind === "IdentifierPattern") {
    const containsSpawn = exprContainsSpawn(ctx, stmt.value);
    const isConsumerResult = stmt.value.kind === "CallExpr" && stmt.value.callee.kind === "Identifier" && (stmt.value.callee.name === "race" || stmt.value.callee.name === "all");
    if (containsSpawn && !isConsumerResult) {
      ctx.unawaitedSpawns.set(stmt.pattern.name, stmt.loc);
      if (stmt.value.kind === "SpawnExpr" && ctx.lastSpawnInWithWasContextDependent && ctx.contextDependentSpawnsInWith)
        ctx.contextDependentSpawnsInWith.add(stmt.pattern.name);
      ctx.lastSpawnInWithWasContextDependent = false;
      transferSpawnTracking(ctx, stmt.value);
    }
  }
  bindPattern(ctx, stmt.pattern, resolvedDeclared, false);
}
function checkVarStmt(ctx, stmt) {
  const declaredType = stmt.type ? astTypeToType(stmt.type) : undefined;
  if (declaredType)
    setExpectedType(stmt.value, declaredType);
  const valueType = ctx.inferExpr(ctx, stmt.value);
  const resolvedDeclared = declaredType ?? valueType;
  if (stmt.type && !isAssignable(valueType, resolvedDeclared, ctx.env)) {
    const err = TypeErrors.typeMismatch(typeToString(resolvedDeclared), typeToString(valueType));
    error(ctx, err.message, stmt.loc, err.hint);
  }
  try {
    ctx.env.define(stmt.name, resolvedDeclared, true);
  } catch (e) {
    const err = TypeErrors.variableAlreadyDefined(stmt.name);
    error(ctx, err.message, stmt.loc, err.hint);
  }
}
function checkAssignStmt(ctx, stmt) {
  const targetType = ctx.inferExpr(ctx, stmt.target);
  setExpectedType(stmt.value, targetType);
  const valueType = ctx.inferExpr(ctx, stmt.value);
  if (stmt.target.kind === "Identifier") {
    const symbol = ctx.env.lookup(stmt.target.name);
    if (symbol && !symbol.mutable) {
      const err = TypeErrors.cannotAssignToImmutable(stmt.target.name);
      error(ctx, err.message, stmt.loc, err.hint);
    }
  }
  if (!isAssignable(valueType, targetType, ctx.env)) {
    const err = TypeErrors.typeMismatch(typeToString(targetType), typeToString(valueType));
    error(ctx, err.message, stmt.loc, err.hint);
  }
}
function isTerminatingStatement(stmt) {
  switch (stmt.kind) {
    case "ReturnStmt":
    case "ThrowStmt":
    case "BreakStmt":
    case "ContinueStmt":
      return true;
    case "IfStmt":
      if (!stmt.else)
        return false;
      const thenTerminates = stmt.then.kind === "Block" ? blockTerminates(stmt.then) : isTerminatingStatement(stmt.then);
      return thenTerminates && blockTerminates(stmt.else);
    case "MatchStmt":
      const hasCatchAll = stmt.arms.some((arm) => arm.pattern.kind === "WildcardPattern" || arm.pattern.kind === "IdentifierPattern" && !arm.guard);
      if (!hasCatchAll)
        return false;
      return stmt.arms.every((arm) => arm.body.kind === "Block" ? blockTerminates(arm.body) : false);
    default:
      return false;
  }
}
function blockTerminates(block) {
  for (const stmt of block.statements)
    if (isTerminatingStatement(stmt))
      return true;
  return false;
}
function checkBlock(ctx, block) {
  const blockEnv = ctx.env.child();
  const savedEnv = ctx.env;
  ctx.env = blockEnv;
  let seenTerminator = false;
  for (const stmt of block.statements) {
    if (seenTerminator) {
      const err = TypeErrors.unreachableCode();
      warning(ctx, `${err.message} at line ${stmt.loc.line}. ${err.hint}`);
    }
    checkStatement(ctx, stmt);
    if (isTerminatingStatement(stmt))
      seenTerminator = true;
  }
  ctx.env = savedEnv;
}

// src/types/passes/infer-types/infer-call.ts
function inferCallExpr(ctx, expr) {
  if (expr.callee.kind === "IndexExpr" && expr.callee.object.kind === "Identifier") {
    const constructorName = expr.callee.object.name;
    const baseTypeCheck = ctx.env.lookupType(constructorName);
    if (baseTypeCheck) {
      recordType(ctx, expr.callee.object, baseTypeCheck);
      const allTypeArgs = [expr.callee.index];
      if (expr.callee.typeArgs)
        allTypeArgs.push(...expr.callee.typeArgs);
      for (const arg of allTypeArgs) {
        if (arg.kind !== "Identifier") {
          const err = TypeErrors.genericParamMustBeIdentifier();
          error(ctx, err.message, arg.loc, err.hint);
        }
      }
      const resolvedTypeArgs = allTypeArgs.map((arg) => resolveTypeName(arg.kind === "Identifier" ? arg.name : "unknown", ctx.env));
      const builtinType = constructGenericType(constructorName, resolvedTypeArgs);
      if (builtinType) {
        const baseType2 = ctx.env.lookupType(constructorName);
        if (baseType2 && baseType2.kind === "object") {
          const typeParams = baseType2.typeParams || [];
          const bindings = new Map;
          for (let i = 0;i < typeParams.length && i < resolvedTypeArgs.length; i++)
            bindings.set(typeParams[i].name, resolvedTypeArgs[i]);
          inferConstructorCall(ctx, expr, substituteTypeInObject(baseType2, bindings));
        }
        return builtinType;
      }
      const baseType = ctx.env.lookupType(constructorName);
      if (baseType && baseType.kind === "object") {
        const typeParams = baseType.typeParams || [];
        const bindings = new Map;
        for (let i = 0;i < typeParams.length && i < resolvedTypeArgs.length; i++)
          bindings.set(typeParams[i].name, resolvedTypeArgs[i]);
        const instantiated = substituteTypeInObject(baseType, bindings);
        inferConstructorCall(ctx, expr, instantiated);
        if (typeParams.length > 0 && resolvedTypeArgs.length > 0)
          return Types.generic(Types.ref(constructorName), resolvedTypeArgs);
        return instantiated;
      }
    }
  }
  const calleeType = ctx.inferExpr(ctx, expr.callee);
  if (expr.callee.kind === "Identifier" && (expr.callee.name === "race" || expr.callee.name === "all")) {
    for (const arg of expr.args)
      consumeSpawnsInExpr(ctx, "kind" in arg ? arg : arg.value);
  } else if (calleeType.kind === "function") {
    for (let i = 0;i < expr.args.length && i < calleeType.params.length; i++) {
      const param = calleeType.params[i];
      if (param && typeInvolvesPromise(param.type, ctx.env)) {
        const arg = expr.args[i];
        const argExpr = arg && "kind" in arg ? arg : arg?.value;
        if (argExpr)
          consumeSpawnsInExpr(ctx, argExpr);
      }
    }
  }
  if (calleeType.kind === "function") {
    recordType(ctx, expr.callee, calleeType);
    return inferFunctionCall(ctx, expr, calleeType);
  }
  if (calleeType.kind === "object") {
    recordType(ctx, expr.callee, calleeType);
    return inferConstructorCall(ctx, expr, calleeType);
  }
  if (calleeType.kind === "interface") {
    error(ctx, `Interface '${calleeType.name}' cannot be constructed; use a type that satisfies the interface`, expr.loc);
    return calleeType;
  }
  for (const arg of expr.args) {
    if ("name" in arg && "value" in arg)
      ctx.inferExpr(ctx, arg.value);
    else
      ctx.inferExpr(ctx, arg);
  }
  return Types.unknown;
}
function inferFunctionCall(ctx, expr, fnType) {
  const args = expr.args;
  const expectedType = getExpectedType(expr);
  const hasNamed = args.some((a) => ("name" in a) && ("value" in a));
  const hasPositional = args.some((a) => !(("name" in a) && ("value" in a)));
  if (hasNamed && hasPositional) {
    const err = TypeErrors.mixedPositionalAndNamedArguments();
    error(ctx, err.message, expr.loc, err.hint);
  }
  let typeBindings = inferTypeParams(ctx, fnType, args);
  if (expectedType && fnType.typeParams?.length) {
    const currentReturn = substituteTypeParams(fnType.returnType, typeBindings);
    unifyTypes(currentReturn, expectedType, typeBindings);
  }
  const params = fnType.params.map((p) => ({ ...p, type: substituteTypeParams(p.type, typeBindings) }));
  const requiredCount = params.filter((p) => !p.optional && !p.rest).length;
  const hasRest = params.some((p) => p.rest);
  const maxArgs = hasRest ? Infinity : params.length;
  if (args.length < requiredCount) {
    const err = TypeErrors.wrongArgumentCount(`at least ${requiredCount}`, args.length);
    error(ctx, err.message, expr.loc, err.hint);
  } else if (args.length > maxArgs) {
    const err = TypeErrors.wrongArgumentCount(`at most ${params.length}`, args.length);
    error(ctx, err.message, expr.loc, err.hint);
  }
  for (let i = 0;i < args.length; i++) {
    const arg = args[i];
    if ("name" in arg && "value" in arg) {
      const param = params.find((p) => p.name === arg.name);
      if (param?.type)
        setExpectedType(arg.value, param.type);
      const argType = ctx.inferExpr(ctx, arg.value);
      if (!param) {
        const err = TypeErrors.unknownParameter(arg.name, params.map((p) => p.name).filter(Boolean));
        error(ctx, err.message, arg.value.loc, err.hint);
      } else if (!isAssignable(argType, param.type, ctx.env)) {
        const err = TypeErrors.typeMismatch(typeToString(param.type), typeToString(argType));
        error(ctx, `Argument '${arg.name}': ${err.message}`, arg.value.loc, err.hint);
      }
    } else {
      const paramIndex = Math.min(i, params.length - 1);
      const param = params[paramIndex];
      const expected = param && (param.rest && param.type.kind === "list" ? param.type : param.type);
      if (expected)
        setExpectedType(arg, expected);
      const argType = ctx.inferExpr(ctx, arg);
      if (param) {
        const expectedType2 = param.rest && param.type.kind === "list" ? param.type.elementType : param.type;
        if (!isAssignable(argType, expectedType2, ctx.env)) {
          const err = TypeErrors.typeMismatch(typeToString(expectedType2), typeToString(argType));
          error(ctx, `Argument ${i + 1}: ${err.message}`, arg.loc, err.hint);
        }
      }
    }
  }
  for (const binding of fnType.context) {
    if (binding.name && !ctx.env.isDefined(binding.name) && !ctx.insideWithContext)
      error(ctx, `No context of type '${typeToString(binding.type)}' available`, expr.loc);
  }
  return substituteTypeParams(fnType.returnType, typeBindings);
}
function inferConstructorCall(ctx, expr, objType) {
  const args = expr.args;
  const hasNamed = args.some((a) => ("name" in a) && ("value" in a));
  const hasPositional = args.some((a) => !(("name" in a) && ("value" in a)));
  if (hasNamed && hasPositional) {
    const err = TypeErrors.mixedPositionalAndNamedArguments();
    error(ctx, err.message, expr.loc, err.hint);
  }
  const ownProps = objType.properties.filter((p) => !p.promotedFrom && !(p.embedded && p.name === "Context"));
  const requiredCount = ownProps.filter((p) => !p.embedded && !p.optional && !p.defaultValue).length;
  const maxArgs = ownProps.length;
  if (args.length < requiredCount) {
    const err = TypeErrors.wrongArgumentCount(`at least ${requiredCount}`, args.length);
    error(ctx, `Type '${objType.name}': ${err.message}`, expr.loc, err.hint);
  } else if (args.length > maxArgs) {
    const err = TypeErrors.wrongArgumentCount(`at most ${maxArgs}`, args.length);
    error(ctx, `Type '${objType.name}': ${err.message}`, expr.loc, err.hint);
  }
  for (let i = 0;i < args.length; i++) {
    const arg = args[i];
    if ("name" in arg && "value" in arg) {
      const prop = ownProps.find((p) => p.name === arg.name);
      const expected = prop ? prop.embedded ? ctx.env.lookupType(prop.name) || Types.unknown : prop.type : undefined;
      if (expected)
        setExpectedType(arg.value, expected);
      const argType = ctx.inferExpr(ctx, arg.value);
      if (!prop) {
        const err = TypeErrors.propertyNotExist(arg.name, objType.name);
        error(ctx, err.message, arg.value.loc, err.hint);
      } else if (!isAssignable(argType, expected, ctx.env)) {
        const err = TypeErrors.typeMismatch(typeToString(expected), typeToString(argType));
        error(ctx, `Property '${arg.name}': ${err.message}`, arg.value.loc, err.hint);
      }
    } else {
      const prop = ownProps[i];
      const expected = prop ? prop.embedded ? ctx.env.lookupType(prop.name) || Types.unknown : prop.type : undefined;
      if (expected)
        setExpectedType(arg, expected);
      const argType = ctx.inferExpr(ctx, arg);
      if (prop && !isAssignable(argType, expected, ctx.env)) {
        const err = TypeErrors.typeMismatch(typeToString(expected), typeToString(argType));
        error(ctx, `Argument ${i + 1}: ${err.message}`, arg.loc, err.hint);
      }
    }
  }
  return objType;
}
function inferTypeParams(ctx, fnType, args) {
  const bindings = new Map;
  if (!fnType.typeParams)
    return bindings;
  for (const tp of fnType.typeParams)
    bindings.set(tp.name, Types.unknown);
  let posIdx = 0;
  for (const arg of args) {
    let paramType;
    if ("name" in arg && "value" in arg) {
      paramType = fnType.params.find((p) => p.name === arg.name)?.type;
    } else {
      paramType = fnType.params[posIdx]?.type;
      posIdx++;
    }
    const expected = paramType ? substituteTypeParams(paramType, bindings) : undefined;
    const argExpr = "name" in arg && "value" in arg ? arg.value : arg;
    if (expected)
      setExpectedType(argExpr, expected);
    const argType = ctx.inferExpr(ctx, argExpr);
    if (paramType)
      unifyTypes(paramType, argType, bindings);
  }
  return bindings;
}

// src/types/passes/infer-types/infer-member.ts
function inferIndexExpr(ctx, expr) {
  if (expr.object.kind === "Identifier") {
    const typeRef = ctx.env.lookupType(expr.object.name);
    if (typeRef) {
      if (expr.index.kind === "Literal" && typeof expr.index.value === "string") {
        error(ctx, "Generic type arguments must be identifiers, not string literals", expr.index.loc);
        return Types.unknown;
      }
      ctx.inferExpr(ctx, expr.index);
      if (expr.typeArgs)
        for (const arg of expr.typeArgs)
          ctx.inferExpr(ctx, arg);
      return typeRef;
    }
  }
  let objectType = ctx.inferExpr(ctx, expr.object);
  if (expr.optional && objectType.kind === "optional")
    objectType = objectType.inner;
  if (expr.slice) {
    if (expr.slice.start) {
      const startType = ctx.inferExpr(ctx, expr.slice.start);
      if (startType.kind !== "number") {
        const err2 = TypeErrors.indexTypeMismatch("number", typeToString(startType));
        error(ctx, `Slice start index: ${err2.message}`, expr.slice.start.loc, err2.hint);
      }
    }
    if (expr.slice.end) {
      const endType = ctx.inferExpr(ctx, expr.slice.end);
      if (endType.kind !== "number") {
        const err2 = TypeErrors.indexTypeMismatch("number", typeToString(endType));
        error(ctx, `Slice end index: ${err2.message}`, expr.slice.end.loc, err2.hint);
      }
    }
    return expr.optional ? Types.optional(objectType) : objectType;
  }
  const indexType = ctx.inferExpr(ctx, expr.index);
  if (objectType.kind === "list") {
    if (indexType.kind !== "number") {
      const err2 = TypeErrors.indexTypeMismatch("number", typeToString(indexType));
      error(ctx, `List index: ${err2.message}`, expr.index.loc, err2.hint);
    }
    const result = objectType.elementType;
    return expr.optional ? Types.optional(result) : result;
  }
  if (objectType.kind === "map") {
    if (!isAssignable(indexType, objectType.keyType, ctx.env)) {
      const err2 = TypeErrors.indexTypeMismatch(typeToString(objectType.keyType), typeToString(indexType));
      error(ctx, `Map key: ${err2.message}`, expr.index.loc, err2.hint);
    }
    return Types.optional(objectType.valueType);
  }
  if (objectType.kind === "string") {
    if (indexType.kind !== "number") {
      const err2 = TypeErrors.indexTypeMismatch("number", typeToString(indexType));
      error(ctx, `String index: ${err2.message}`, expr.index.loc, err2.hint);
    }
    return expr.optional ? Types.optional(Types.string) : Types.string;
  }
  if (objectType.kind === "unknown") {
    const err2 = TypeErrors.operationNotAllowedOnUnknown("[]");
    error(ctx, err2.message, expr.loc, err2.hint);
    return expr.optional ? Types.optional(Types.unknown) : Types.unknown;
  }
  const err = TypeErrors.indexAccessOnInvalidType(typeToString(objectType));
  error(ctx, err.message, expr.loc, err.hint);
  return expr.optional ? Types.optional(Types.unknown) : Types.unknown;
}
function inferMemberExpr(ctx, expr) {
  if (expr.object.kind === "Identifier") {
    const symbol = ctx.env.lookup(expr.object.name);
    if (!symbol) {
      const typeRef = ctx.env.lookupType(expr.object.name);
      if (typeRef && typeRef.kind === "object") {
        const err = TypeErrors.memberAccessOnType(expr.object.name);
        error(ctx, err.message, expr.loc, err.hint);
        return Types.unknown;
      }
    }
  }
  const objectType = ctx.inferExpr(ctx, expr.object);
  if (objectType.kind === "unknown") {
    const err = TypeErrors.operationNotAllowedOnUnknown(".");
    error(ctx, err.message, expr.loc, err.hint);
    return Types.unknown;
  }
  let resolved = ctx.env.resolveType(objectType);
  if (resolved.kind === "function") {
    const err = TypeErrors.memberAccessOnFunction();
    error(ctx, err.message, expr.loc, err.hint);
    return Types.unknown;
  }
  if (resolved.kind === "generic" && resolved.base.kind === "ref") {
    const baseType = ctx.env.lookupType(resolved.base.name);
    if (baseType && baseType.kind === "object") {
      const typeParams = baseType.typeParams || [];
      const bindings = new Map;
      for (let i = 0;i < typeParams.length && i < resolved.args.length; i++)
        bindings.set(typeParams[i].name, resolved.args[i]);
      resolved = substituteTypeInObject(baseType, bindings);
    }
  }
  if (resolved.kind === "interface") {
    const method = resolved.methods.find((m) => m.name === expr.property);
    if (method)
      return method.type;
    if (!expr.optional) {
      const err = TypeErrors.propertyNotExist(expr.property, resolved.name);
      error(ctx, err.message, expr.loc, err.hint);
    }
    return Types.unknown;
  }
  if (resolved.kind === "object") {
    const prop = resolved.properties.find((p) => p.name === expr.property);
    if (prop) {
      if (expr.property.startsWith("_") && resolved.name && ctx.currentTypeName !== resolved.name) {
        const err = TypeErrors.privateAccess(expr.property, resolved.name);
        error(ctx, err.message, expr.loc, err.hint);
      }
      return expr.optional ? Types.optional(prop.type) : prop.type;
    }
    const method = resolved.methods.find((m) => m.name === expr.property);
    if (method) {
      if (expr.property.startsWith("_") && resolved.name && ctx.currentTypeName !== resolved.name) {
        const err = TypeErrors.privateAccess(expr.property, resolved.name);
        error(ctx, err.message, expr.loc, err.hint);
      }
      return method.type;
    }
    if (resolved.name && !expr.optional) {
      const err = TypeErrors.propertyNotExist(expr.property, resolved.name);
      error(ctx, err.message, expr.loc, err.hint);
    }
  }
  return inferBuiltinMember(ctx, objectType, expr);
}
function inferBuiltinMember(ctx, objectType, expr) {
  const member = ctx.env.lookupBuiltinMethod(objectType.kind, expr.property);
  if (member)
    return substituteBuiltinTypeParams(member.type, objectType);
  if (objectType.kind === "map")
    return expr.optional ? Types.optional(objectType.valueType) : objectType.valueType;
  if (objectType.kind === "unknown") {
    const err = TypeErrors.operationNotAllowedOnUnknown(".");
    error(ctx, err.message, expr.loc, err.hint);
    return Types.unknown;
  }
  if (objectType.kind === "number" || objectType.kind === "bool" || objectType.kind === "string" || objectType.kind === "list" || objectType.kind === "set") {
    if (!expr.optional)
      error(ctx, `Property '${expr.property}' does not exist on type '${objectType.kind}'`, expr.loc);
    return expr.optional ? Types.optional(Types.unknown) : Types.unknown;
  }
  return expr.optional ? Types.optional(Types.unknown) : Types.unknown;
}
function substituteBuiltinTypeParams(type, objectType) {
  const bindings = new Map;
  if (objectType.kind === "list" || objectType.kind === "set" || objectType.kind === "channel")
    bindings.set("T", objectType.elementType);
  else if (objectType.kind === "map") {
    bindings.set("K", objectType.keyType);
    bindings.set("V", objectType.valueType);
  }
  if (bindings.size === 0)
    return type;
  return substituteTypeParams(type, bindings);
}
function inferPipeExpr(ctx, expr) {
  const leftType = ctx.inferExpr(ctx, expr.left);
  const expectedPipeFn = Types.fn([Types.param("_", leftType)], Types.unknown);
  setExpectedType(expr.right, expectedPipeFn);
  if (expr.right.kind === "CallExpr") {
    const callExpr = expr.right;
    setExpectedType(callExpr.callee, expectedPipeFn);
    const calleeType = ctx.inferExpr(ctx, callExpr.callee);
    if (calleeType.kind === "function") {
      const syntheticArgs = [expr.left, ...callExpr.args];
      const typeBindings = inferTypeParams(ctx, calleeType, syntheticArgs);
      const params = calleeType.params.map((p) => ({ ...p, type: substituteTypeParams(p.type, typeBindings) }));
      const requiredCount = params.filter((p) => !p.optional && !p.rest).length;
      if (1 + callExpr.args.length < requiredCount) {
        const err = TypeErrors.wrongArgumentCount(`at least ${requiredCount}`, 1 + callExpr.args.length);
        error(ctx, err.message, callExpr.loc, err.hint);
      }
      if (params.length > 0) {
        if (!isAssignable(leftType, params[0].type, ctx.env)) {
          const err = TypeErrors.typeMismatch(typeToString(params[0].type), typeToString(leftType));
          error(ctx, `Pipe argument: ${err.message}`, expr.left.loc, err.hint);
        }
      }
      for (let i = 0;i < callExpr.args.length; i++) {
        const arg = callExpr.args[i];
        const paramIndex = i + 1;
        const param = paramIndex < params.length ? params[paramIndex] : params[params.length - 1];
        if (param) {
          let argType, argLoc;
          if ("name" in arg && "value" in arg) {
            argType = ctx.inferExpr(ctx, arg.value);
            argLoc = arg.value.loc;
          } else {
            argType = ctx.inferExpr(ctx, arg);
            argLoc = arg.loc;
          }
          const expected = param.rest && param.type.kind === "list" ? param.type.elementType : param.type;
          if (!isAssignable(argType, expected, ctx.env)) {
            const err = TypeErrors.typeMismatch(typeToString(expected), typeToString(argType));
            error(ctx, `Argument ${paramIndex + 1}: ${err.message}`, argLoc, err.hint);
          }
        }
      }
      return substituteTypeParams(calleeType.returnType, typeBindings);
    }
    for (const arg of callExpr.args) {
      if ("name" in arg && "value" in arg)
        ctx.inferExpr(ctx, arg.value);
      else
        ctx.inferExpr(ctx, arg);
    }
    return Types.unknown;
  }
  const rightType = ctx.inferExpr(ctx, expr.right);
  if (rightType.kind === "function")
    return rightType.returnType;
  return Types.unknown;
}

// src/types/passes/infer-types/infer-expr.ts
function expectedFunctionType(expected) {
  if (!expected)
    return;
  if (expected.kind === "function")
    return expected;
  return;
}
function expectedCollectionType(expected) {
  if (!expected)
    return;
  if (expected.kind === "list" || expected.kind === "map")
    return expected;
  if (expected.kind === "optional" && expected.inner)
    return expectedCollectionType(expected.inner);
  return;
}
function inferExpr(ctx, expr) {
  const expectedType = getExpectedType(expr);
  let type;
  switch (expr.kind) {
    case "Literal":
      type = inferLiteral(expr);
      break;
    case "Identifier":
      type = inferIdentifier(ctx, expr);
      break;
    case "BinaryExpr":
      type = inferBinaryExpr(ctx, expr);
      break;
    case "UnaryExpr":
      type = inferUnaryExpr(ctx, expr);
      break;
    case "CallExpr":
      type = inferCallExpr(ctx, expr);
      break;
    case "IndexExpr":
      type = inferIndexExpr(ctx, expr);
      break;
    case "MemberExpr":
      type = inferMemberExpr(ctx, expr);
      break;
    case "PipeExpr":
      type = inferPipeExpr(ctx, expr);
      break;
    case "LambdaExpr":
      type = inferLambdaExpr(ctx, expr, expectedFunctionType(expectedType));
      break;
    case "IfExpr":
      type = inferIfExpr(ctx, expr);
      break;
    case "MatchExpr":
      type = inferMatchExpr(ctx, expr);
      break;
    case "ListExpr":
      type = inferListExpr(ctx, expr, expectedCollectionType(expectedType));
      break;
    case "SetExpr":
      type = inferSetExpr(ctx, expr, expectedCollectionType(expectedType));
      break;
    case "MapExpr":
      type = inferMapExpr(ctx, expr, expectedCollectionType(expectedType));
      break;
    case "SpawnExpr":
      type = inferSpawnExpr(ctx, expr);
      break;
    case "TypeAssertion": {
      const exprType = inferExpr(ctx, expr.expr);
      const assertedType = astTypeToType(expr.type);
      const canAssert = exprType.kind === "unknown" || assertedType.kind === "unknown" || isAssignable(exprType, assertedType, ctx.env) || isAssignable(assertedType, exprType, ctx.env);
      if (!canAssert) {
        const err = TypeErrors.invalidTypeAssertion(typeToString(exprType), typeToString(assertedType));
        error(ctx, err.message, expr.loc, err.hint);
      }
      type = assertedType;
      break;
    }
    case "NullAssertion": {
      const innerType = inferExpr(ctx, expr.expr);
      if (!isNullable(innerType)) {
        const err = TypeErrors.unnecessaryNullAssertion(typeToString(innerType));
        warning(ctx, `${err.message}. ${err.hint}`);
      }
      type = nonNull(innerType);
      break;
    }
    case "RangeExpr":
      type = Types.list(Types.number);
      break;
    case "TemplateLiteral":
      type = inferTemplateLiteral(ctx, expr);
      break;
    default:
      type = Types.unknown;
  }
  recordType(ctx, expr, type);
  return type;
}
function inferLiteral(expr) {
  if (typeof expr.value === "number")
    return Types.number;
  if (typeof expr.value === "string")
    return Types.string;
  if (typeof expr.value === "boolean")
    return Types.bool;
  if (expr.value === null)
    return Types.null;
  return Types.unknown;
}
function inferIdentifier(ctx, expr) {
  const symbol = ctx.env.lookup(expr.name);
  if (!symbol) {
    const typeRef = ctx.env.lookupType(expr.name);
    if (typeRef) {
      if (typeRef.kind === "object" && typeRef.name) {
        const obj = typeRef;
        const ownProps = obj.properties.filter((p) => !p.promotedFrom);
        const params = [];
        for (const p of ownProps) {
          if (p.embedded) {
            const embeddedType = ctx.env.lookupType(p.name);
            params.push(Types.param(p.name, embeddedType || Types.unknown, true));
          } else {
            params.push(Types.param(p.name, p.type, p.optional || !!p.defaultValue));
          }
        }
        const fnType = {
          kind: "function",
          params,
          returnType: obj.typeParams && obj.typeParams.length > 0 ? Types.generic(Types.ref(obj.name), obj.typeParams.map((tp) => Types.typevar(tp.name))) : typeRef,
          isGenerator: false,
          context: [],
          typeParams: obj.typeParams?.map((tp) => ({ name: tp.name, constraint: tp.constraint }))
        };
        return fnType;
      }
      return typeRef;
    }
    const err = TypeErrors.unknownIdentifier(expr.name);
    error(ctx, err.message, expr.loc, err.hint);
    return Types.unknown;
  }
  return symbol.type;
}
function inferBinaryExpr(ctx, expr) {
  const leftType = inferExpr(ctx, expr.left);
  const rightType = inferExpr(ctx, expr.right);
  switch (expr.op) {
    case "+":
      if (leftType.kind === "unknown" || rightType.kind === "unknown") {
        const err = TypeErrors.operationNotAllowedOnUnknown("+");
        error(ctx, err.message, expr.loc, err.hint);
      }
      if (leftType.kind === "string" || rightType.kind === "string")
        return Types.string;
      if (leftType.kind !== "number") {
        const err = TypeErrors.operatorRequiresType("+", "number or string", typeToString(leftType));
        error(ctx, err.message, expr.left.loc, err.hint);
      }
      if (rightType.kind !== "number") {
        const err = TypeErrors.operatorRequiresType("+", "number or string", typeToString(rightType));
        error(ctx, err.message, expr.right.loc, err.hint);
      }
      return Types.number;
    case "-":
    case "*":
    case "/":
    case "%":
    case "^":
      if (leftType.kind === "unknown" || rightType.kind === "unknown") {
        const err = TypeErrors.operationNotAllowedOnUnknown(expr.op);
        error(ctx, err.message, expr.loc, err.hint);
      }
      if (leftType.kind !== "number") {
        const err = TypeErrors.operatorRequiresType(expr.op, "number", typeToString(leftType));
        error(ctx, err.message, expr.left.loc, err.hint);
      }
      if (rightType.kind !== "number") {
        const err = TypeErrors.operatorRequiresType(expr.op, "number", typeToString(rightType));
        error(ctx, err.message, expr.right.loc, err.hint);
      }
      return Types.number;
    case "<":
    case ">":
    case "<=":
    case ">=": {
      if (leftType.kind === "unknown" || rightType.kind === "unknown") {
        const err = TypeErrors.operationNotAllowedOnUnknown(expr.op);
        error(ctx, err.message, expr.loc, err.hint);
      }
      const leftBase = leftType.kind === "optional" ? leftType.inner : leftType;
      const rightBase = rightType.kind === "optional" ? rightType.inner : rightType;
      if (leftBase.kind !== rightBase.kind && !((leftBase.kind === "number" || leftBase.kind === "string") && (rightBase.kind === "number" || rightBase.kind === "string"))) {
        const err = TypeErrors.cannotCompare(typeToString(leftType), typeToString(rightType));
        error(ctx, err.message, expr.loc, err.hint);
      }
      return Types.bool;
    }
    case "==":
    case "!=":
      if (leftType.kind === "unknown" || rightType.kind === "unknown") {
        const err = TypeErrors.operationNotAllowedOnUnknown(expr.op);
        error(ctx, err.message, expr.loc, err.hint);
      }
      return Types.bool;
    case "and":
    case "or":
    case "is":
      return Types.bool;
    case "??":
      if (isNullable(leftType))
        return Types.union(nonNull(leftType), rightType);
      return leftType;
    default:
      return Types.unknown;
  }
}
function inferUnaryExpr(ctx, expr) {
  const operandType = inferExpr(ctx, expr.operand);
  switch (expr.op) {
    case "-":
      if (operandType.kind === "unknown") {
        const err = TypeErrors.operationNotAllowedOnUnknown("-");
        error(ctx, err.message, expr.operand.loc, err.hint);
      }
      if (operandType.kind !== "number") {
        const err = TypeErrors.operatorRequiresType("-", "number", typeToString(operandType));
        error(ctx, err.message, expr.operand.loc, err.hint);
      }
      return Types.number;
    case "not":
    case "!":
      return Types.bool;
    default:
      return operandType;
  }
}
function inferLambdaExpr(ctx, expr, expectedFn) {
  const restParam = expectedFn?.params.find((p) => p.rest);
  const restElementType = restParam?.type.kind === "list" ? restParam.type.elementType : undefined;
  const params = expr.params.map((p, i) => {
    let type;
    if (p.type) {
      type = astTypeToType(p.type);
    } else if (expectedFn?.params) {
      if (p.rest) {
        type = restElementType ?? Types.unknown;
      } else {
        const expectedParam = expectedFn.params[i] ?? (restParam && restElementType ? { type: restElementType } : null);
        type = expectedParam?.type ?? Types.unknown;
      }
    } else {
      type = Types.unknown;
    }
    return { name: p.name, type, optional: p.optional, rest: p.rest };
  });
  const lambdaEnv = ctx.env.child();
  for (const param of params)
    lambdaEnv.define(param.name, param.type);
  const savedEnv = ctx.env;
  ctx.env = lambdaEnv;
  let returnType;
  if (expr.body.kind === "Block") {
    ctx.checkBlock(ctx, expr.body);
    returnType = Types.void;
  } else {
    returnType = inferExpr(ctx, expr.body);
  }
  ctx.env = savedEnv;
  return Types.fn(params, returnType);
}
function inferIfExpr(ctx, expr) {
  const expectedType = getExpectedType(expr);
  inferExpr(ctx, expr.condition);
  if (expectedType) {
    setExpectedType(expr.then, expectedType);
    setExpectedType(expr.else, expectedType);
  }
  const thenType = inferExpr(ctx, expr.then);
  const elseType = inferExpr(ctx, expr.else);
  if (isAssignable(thenType, elseType, ctx.env))
    return elseType;
  if (isAssignable(elseType, thenType, ctx.env))
    return thenType;
  return Types.union(thenType, elseType);
}
function inferMatchExpr(ctx, expr) {
  const valueType = inferExpr(ctx, expr.value);
  const expectedType = getExpectedType(expr);
  const armTypes = [];
  for (const arm of expr.arms) {
    const armEnv = ctx.env.child();
    const savedEnv = ctx.env;
    ctx.env = armEnv;
    checkPattern(ctx, arm.pattern, valueType);
    if (arm.guard)
      inferExpr(ctx, arm.guard);
    let armType;
    if (arm.body.kind === "Block") {
      ctx.checkBlock(ctx, arm.body);
      armType = Types.void;
    } else {
      if (expectedType)
        setExpectedType(arm.body, expectedType);
      armType = inferExpr(ctx, arm.body);
    }
    armTypes.push(armType);
    ctx.env = savedEnv;
  }
  if (armTypes.length === 0)
    return Types.never;
  if (armTypes.length === 1)
    return armTypes[0];
  return Types.union(...armTypes);
}
function inferListExpr(ctx, expr, expected) {
  if (expr.elements.length === 0) {
    if (expected?.kind === "list")
      return Types.list(expected.elementType);
    return Types.list(Types.unknown);
  }
  const elementTypes = [];
  for (const el of expr.elements) {
    if (el.kind === "SpreadElement") {
      const spreadType = inferExpr(ctx, el.expr);
      if (spreadType.kind === "list")
        elementTypes.push(spreadType.elementType);
      if (el.expr.kind === "Identifier")
        ctx.unawaitedSpawns.delete(el.expr.name);
    } else {
      elementTypes.push(inferExpr(ctx, el));
      if (el.kind === "Identifier")
        ctx.unawaitedSpawns.delete(el.name);
    }
  }
  return Types.list(findCommonType(elementTypes));
}
function inferSetExpr(ctx, expr, expected) {
  if (expr.elements.length === 0) {
    if (expected?.kind === "set")
      return Types.set(expected.elementType);
    return Types.set(Types.unknown);
  }
  const elementTypes = expr.elements.map((el) => inferExpr(ctx, el));
  for (const el of expr.elements)
    if (el.kind === "Identifier")
      ctx.unawaitedSpawns.delete(el.name);
  return Types.set(findCommonType(elementTypes));
}
function inferMapExpr(ctx, expr, expected) {
  if (expr.entries.length === 0) {
    if (expected?.kind === "map")
      return Types.map(expected.keyType, expected.valueType);
    return Types.map(Types.string, Types.unknown);
  }
  const keyTypes = [];
  const valueTypes = [];
  for (const entry of expr.entries) {
    if (!entry.spread) {
      if (entry.key.kind === "Identifier") {
        if (RESERVED_PROPERTY_NAMES.has(entry.key.name)) {
          const err = TypeErrors.reservedPropertyName(entry.key.name);
          error(ctx, err.message, entry.key.loc, err.hint);
        }
        keyTypes.push(Types.string);
      } else {
        keyTypes.push(inferExpr(ctx, entry.key));
      }
      valueTypes.push(inferExpr(ctx, entry.value));
    }
  }
  return Types.map(findCommonType(keyTypes), findCommonType(valueTypes));
}
function inferTemplateLiteral(ctx, expr) {
  for (const part of expr.parts) {
    if (typeof part !== "string")
      inferExpr(ctx, part.expr);
  }
  return Types.string;
}

// src/types/passes/infer-types/index.ts
function inferTypes(input) {
  const { program, env, fnDecls } = input;
  const ctx = createInferContext(env, fnDecls, { inferExpr, checkStatement, checkBlock });
  for (const stmt of program.body) {
    checkStatement(ctx, stmt);
  }
  for (const [name, loc] of ctx.unawaitedSpawns) {
    error(ctx, `spawn result '${name}' is never awaited (pass to race() or all())`, loc);
  }
  return { errors: ctx.errors, warnings: ctx.warnings };
}

// src/types/passes/infer-types-pass.ts
class InferTypesPass {
  name = "infer-types";
  run(ctx) {
    const result = inferTypes({
      program: ctx.program,
      env: ctx.env,
      fnDecls: ctx.fnDecls
    });
    ctx.errors.push(...result.errors);
    ctx.warnings.push(...result.warnings);
  }
}

// src/types/pass-manager.ts
class PassManager {
  passes = [];
  static createDefault() {
    const mgr = new PassManager;
    mgr.addPass(new CollectDeclarationsPass);
    mgr.addPass(new InferTypesPass);
    return mgr;
  }
  addPass(pass) {
    this.passes.push(pass);
    return this;
  }
  removePass(name) {
    this.passes = this.passes.filter((p) => p.name !== name);
    return this;
  }
  insertBefore(existingName, pass) {
    const idx = this.passes.findIndex((p) => p.name === existingName);
    if (idx === -1) {
      this.passes.push(pass);
    } else {
      this.passes.splice(idx, 0, pass);
    }
    return this;
  }
  insertAfter(existingName, pass) {
    const idx = this.passes.findIndex((p) => p.name === existingName);
    if (idx === -1) {
      this.passes.push(pass);
    } else {
      this.passes.splice(idx + 1, 0, pass);
    }
    return this;
  }
  getPassNames() {
    return this.passes.map((p) => p.name);
  }
  run(program) {
    return this.runWithEnv(program, createGlobalEnvironment());
  }
  runWithEnv(program, initialEnv) {
    const ctx = {
      program,
      env: initialEnv,
      fnDecls: new Map,
      errors: [],
      warnings: []
    };
    for (const pass of this.passes) {
      pass.run(ctx);
    }
    return {
      program: ctx.program,
      env: ctx.env,
      errors: ctx.errors,
      warnings: ctx.warnings
    };
  }
}

// src/types/checker.ts
class TypeChecker {
  manager;
  constructor() {
    this.manager = PassManager.createDefault();
  }
  check(program) {
    const env = createGlobalEnvironment();
    const stdlibErrors = resolveStdlibImports(program, env);
    const result = this.manager.runWithEnv(program, env);
    result.errors.unshift(...stdlibErrors);
    return result;
  }
}

// src/builtin/compiled.ts
function hasExternMethods(stmt) {
  if (stmt.kind !== "TypeDecl" || !stmt.body?.members)
    return false;
  return stmt.body.members.some((m) => m.kind === "MethodDecl" && m.isExtern);
}
function compileSource(source) {
  const ast2 = new Parser(source).parse();
  new TypeChecker().check(ast2);
  const codegen = new CodeGenerator({ emitRuntimeImport: false });
  const exportNames = [];
  const code = [];
  for (const stmt of ast2.body) {
    if (stmt.kind === "ExternFnDecl")
      continue;
    if (hasExternMethods(stmt))
      continue;
    const name = stmt.name;
    if (stmt.kind === "FnDecl" || stmt.kind === "TypeDecl") {
      if (name && !name.startsWith("_")) {
        exportNames.push(name);
      }
    }
    const singleProgram = { kind: "Program", body: [stmt], loc: stmt.loc };
    const stmtCode = codegen.generate(singleProgram);
    code.push(stmtCode);
  }
  return { code, exportNames };
}
function compileAll() {
  const allCode = [];
  const allExports = [];
  const builtins = compileSource(builtinsSource);
  allCode.push(...builtins.code);
  allExports.push(...builtins.exportNames);
  for (const [, source] of getAllStdlibSources()) {
    const result = compileSource(source);
    allCode.push(...result.code);
    allExports.push(...result.exportNames);
  }
  const moduleCode = `
    "use strict";
    ${allCode.join(`
`)}
    return { ${allExports.join(", ")} };
  `;
  return new Function("__ms_runtime", moduleCode);
}
var compiledBuiltins = null;
function getCompiledBuiltins(runtime) {
  if (!compiledBuiltins) {
    const factory = compileAll();
    compiledBuiltins = factory(runtime);
  }
  return compiledBuiltins;
}

// src/runtime/concurrency.ts
class Channel {
  buffer = [];
  capacity;
  closed = false;
  sendWaiters = [];
  recvWaiters = [];
  constructor(capacity = 0) {
    this.capacity = capacity;
  }
  async send(value) {
    if (this.closed)
      throw new Error("Cannot send on closed channel");
    if (this.recvWaiters.length > 0) {
      const waiter = this.recvWaiters.shift();
      waiter.resolve(value);
      return;
    }
    if (this.buffer.length < this.capacity) {
      this.buffer.push(value);
      return;
    }
    return new Promise((resolve2) => {
      this.sendWaiters.push({ value, resolve: resolve2 });
    });
  }
  async receive() {
    if (this.buffer.length > 0) {
      const value = this.buffer.shift();
      if (this.sendWaiters.length > 0) {
        const waiter = this.sendWaiters.shift();
        this.buffer.push(waiter.value);
        waiter.resolve();
      }
      return value;
    }
    if (this.sendWaiters.length > 0) {
      const waiter = this.sendWaiters.shift();
      waiter.resolve();
      return waiter.value;
    }
    if (this.closed)
      return;
    return new Promise((resolve2) => {
      this.recvWaiters.push({ resolve: resolve2 });
    });
  }
  close() {
    this.closed = true;
    for (const waiter of this.recvWaiters) {
      waiter.resolve(undefined);
    }
    this.recvWaiters = [];
  }
  isClosed() {
    return this.closed;
  }
  [Symbol.asyncIterator]() {
    return {
      next: async () => {
        const value = await this.receive();
        if (value === undefined && this.closed) {
          return { done: true, value: undefined };
        }
        return { done: false, value };
      }
    };
  }
}
function spawn(fn) {
  return fn();
}
function sleep(ms) {
  return new Promise((resolve2) => setTimeout(resolve2, ms));
}
async function all_settled(promises) {
  return Promise.all(promises);
}
async function race(promises) {
  return Promise.race(promises);
}
async function timeout(ms, promise) {
  return Promise.race([
    promise,
    new Promise((_, reject) => setTimeout(() => reject(new Error("Timeout")), ms))
  ]);
}
function delay(ms) {
  return sleep(ms);
}
// src/runtime/testing.ts
var tests = [];
function test(description, fn) {
  tests.push({ description, fn });
}
function getTestCount() {
  return tests.length;
}
function clearTests() {
  tests.length = 0;
}
async function runTests() {
  let passed = 0;
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log(`\u2713 ${t.description}`);
      passed++;
    } catch (e) {
      console.error(`\u2717 ${t.description}`);
      console.error(`  ${e}`);
      failed++;
    }
  }
  console.log(`
${passed} passed, ${failed} failed`);
  return { passed, failed };
}
async function runTestsWithResults() {
  const results = [];
  for (const t of tests) {
    try {
      await t.fn();
      results.push({ name: t.description, passed: true });
    } catch (e) {
      results.push({ name: t.description, passed: false, error: e?.message || String(e) });
    }
  }
  return results;
}
// src/runtime/runtime.ts
var Context$methods = Object.assign(Object.create(null), {
  close() {}
});
function Context() {
  return Object.create(Context$methods);
}
var __contextStack = [];
function __pushContext() {
  __contextStack.push(new Map);
}
function __popContext() {
  __contextStack.pop();
}
function __setContext(typeName, value) {
  const current = __contextStack[__contextStack.length - 1];
  if (current)
    current.set(typeName, value);
}
function __getContext(typeName) {
  for (let i = __contextStack.length - 1;i >= 0; i--) {
    const scope = __contextStack[i];
    if (scope?.has(typeName))
      return scope.get(typeName);
  }
  throw new Error(`No context of type '${typeName}' available. Use 'with' to provide it.`);
}
function print(...args) {
  console.log(...args);
}
function log(...args) {
  console.log(...args);
}
function now() {
  return Date.now();
}
function typeOf(x) {
  if (x === null)
    return "null";
  if (Array.isArray(x))
    return "list";
  if (x instanceof Map)
    return "map";
  if (x instanceof Set)
    return "set";
  if (x instanceof Channel)
    return "channel";
  if (typeof x === "object" && x.__typename) {
    return x.__typename;
  }
  if (typeof x === "object" && x.constructor && x.constructor.name !== "Object") {
    return x.constructor.name;
  }
  return typeof x;
}
function clone(x) {
  if (x === null || typeof x !== "object")
    return x;
  if (Array.isArray(x))
    return [...x];
  if (x instanceof Map)
    return new Map(x);
  if (x instanceof Set)
    return new Set(x);
  return { ...x };
}
function hash(x) {
  const str = JSON.stringify(x);
  let h = 0;
  for (let i = 0;i < str.length; i++) {
    h = (h << 5) - h + str.charCodeAt(i);
    h |= 0;
  }
  return h;
}
function to_str(x) {
  if (x === null)
    return "null";
  if (typeof x === "object") {
    if (x.__typename)
      return x.__typename;
    return JSON.stringify(x);
  }
  return String(x);
}
function to_num(s) {
  return Number(s);
}
function to_json(x) {
  return JSON.stringify(x);
}
function from_json(s) {
  return JSON.parse(s);
}
function len(x) {
  if (typeof x === "string" || Array.isArray(x))
    return x.length;
  if (x instanceof Map || x instanceof Set)
    return x.size;
  if (typeof x === "object" && x !== null)
    return Object.keys(x).length;
  return 0;
}
function keys(map) {
  if (map instanceof Map)
    return Array.from(map.keys());
  return Object.keys(map);
}
function values(map) {
  if (map instanceof Map)
    return Array.from(map.values());
  return Object.values(map);
}
function entries(map) {
  if (map instanceof Map)
    return Array.from(map.entries());
  return Object.entries(map);
}
function sort(list) {
  return [...list].sort();
}
function upper(s) {
  return s.toUpperCase();
}
function lower(s) {
  return s.toLowerCase();
}
function trim(s) {
  return s.trim();
}
function split(s, delim) {
  return s.split(delim);
}
function join(list, delim) {
  return list.join(delim);
}
function replace(s, old, replacement) {
  return s.replaceAll(old, replacement);
}
function starts_with(s, prefix) {
  return s.startsWith(prefix);
}
function ends_with(s, suffix) {
  return s.endsWith(suffix);
}
function substring(s, start, end) {
  return s.substring(start, end);
}
function matches(s, pattern) {
  return new RegExp(pattern).test(s);
}
var sqrt = Math.sqrt;
var pow = Math.pow;
var floor = Math.floor;
var ceil = Math.ceil;
var round = Math.round;
function random() {
  return Math.random();
}
function random_int(minVal, maxVal) {
  return Math.floor(Math.random() * (maxVal - minVal + 1)) + minVal;
}
function panic(message) {
  throw new Error(message);
}
function error2(message, cause) {
  const err = new Error(message);
  if (cause)
    err.cause = cause;
  return err;
}
function range(start, end, inclusive = false) {
  const result = [];
  const stop = inclusive ? end + 1 : end;
  for (let i = start;i < stop; i++)
    result.push(i);
  return result;
}
function template(_name, parts) {
  return parts.map((p) => String(p)).join("");
}
function setFromList(list) {
  return new Set(list);
}
function setUnion(a, b) {
  return new Set([...a, ...b]);
}
function setIntersect(a, b) {
  return new Set([...a].filter((x) => b.has(x)));
}
function setDifference(a, b) {
  return new Set([...a].filter((x) => !b.has(x)));
}
function setIsSubset(a, b) {
  return [...a].every((x) => b.has(x));
}
var __ms_runtime = {
  Context,
  Channel,
  __pushContext,
  __popContext,
  __setContext,
  __getContext,
  test,
  getTestCount,
  clearTests,
  runTests,
  runTestsWithResults,
  spawn,
  sleep,
  all_settled,
  race,
  timeout,
  delay,
  range,
  template,
  print,
  log,
  now,
  typeof: typeOf,
  clone,
  hash,
  to_str,
  to_num,
  to_json,
  from_json,
  len,
  keys,
  values,
  entries,
  sort,
  upper,
  lower,
  trim,
  split,
  join,
  replace,
  starts_with,
  ends_with,
  substring,
  matches,
  sqrt,
  pow,
  floor,
  ceil,
  round,
  random,
  random_int,
  panic,
  error: error2,
  set: setFromList,
  union: setUnion,
  intersect: setIntersect,
  difference: setDifference,
  is_subset: setIsSubset
};
Object.assign(__ms_runtime, getCompiledBuiltins(__ms_runtime));
export {
  timeout,
  test,
  spawn,
  sleep,
  runTestsWithResults,
  runTests,
  race,
  getTestCount,
  delay,
  clearTests,
  all_settled,
  __setContext,
  __pushContext,
  __popContext,
  __ms_runtime,
  __getContext,
  Context,
  Channel
};
