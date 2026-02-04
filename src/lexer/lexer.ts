import type { Token, TokenType, SourceLocation } from "./tokens";
import { KEYWORDS } from "./tokens";
import { LexerErrors } from "../shared/errors";

export class LexerError extends Error {
  constructor(
    message: string,
    public loc: SourceLocation,
    public hint?: string
  ) {
    super(`${message} at line ${loc.line}, column ${loc.column}`);
    this.name = "LexerError";
  }
}

export class Lexer {
  private source: string;
  private pos: number = 0;
  private line: number = 1;
  private column: number = 1;
  private tokens: Token[] = [];
  private indentStack: number[] = [0];
  private atLineStart: boolean = true;
  private pendingTokens: Token[] = [];
  private pendingComment: string | undefined;
  private pendingCommentLine: number = 0;

  constructor(source: string) {
    this.source = source;
  }

  tokenize(): Token[] {
    while (!this.isAtEnd()) {
      this.scanToken();
    }

    // Emit remaining DEDENTs at EOF
    while (this.indentStack.length > 1) {
      this.indentStack.pop();
      this.tokens.push(this.makeToken("DEDENT", null, ""));
    }

    this.tokens.push(this.makeToken("EOF", null, ""));
    return this.tokens;
  }

  private scanToken(): void {
    // Handle indentation at line start
    if (this.atLineStart) {
      this.handleIndentation();
      this.atLineStart = false;
      if (this.isAtEnd()) return;
    }

    const char = this.peek();

    // Skip whitespace (but not newlines)
    if (char === " " || char === "\t") {
      this.advance();
      return;
    }

    // Comments
    if (char === "/" && this.peekNext() === "/") {
      this.skipComment();
      return;
    }

    // Newlines
    if (char === "\n") {
      this.handleNewline();
      return;
    }

    // Carriage return (handle \r\n)
    if (char === "\r") {
      this.advance();
      if (this.peek() === "\n") {
        this.handleNewline();
      }
      return;
    }

    // Strings
    if (char === '"') {
      this.scanString();
      return;
    }

    // Raw strings
    if (char === "r" && this.peekNext() === '"') {
      this.scanRawString();
      return;
    }

    // Byte strings
    if (char === "b" && this.peekNext() === '"') {
      this.scanByteString();
      return;
    }

    // Numbers
    if (this.isDigit(char)) {
      this.scanNumber();
      return;
    }

    // Identifiers and keywords
    if (this.isAlpha(char)) {
      this.scanIdentifier();
      return;
    }

    // Operators and delimiters
    this.scanOperator();
  }

  private handleIndentation(): void {
    let indent = 0;
    while (this.peek() === " ") {
      indent++;
      this.advance();
    }
    // Skip tabs (convert to spaces, 1 tab = 2 spaces for now)
    while (this.peek() === "\t") {
      indent += 2;
      this.advance();
    }

    // Skip empty lines and comment-only lines
    if (this.peek() === "\n" || this.peek() === "\r" || 
        (this.peek() === "/" && this.peekNext() === "/")) {
      return;
    }

    // Skip if at EOF
    if (this.isAtEnd()) return;

    const currentIndent = this.indentStack[this.indentStack.length - 1]!;

    if (indent > currentIndent) {
      this.indentStack.push(indent);
      this.tokens.push(this.makeToken("INDENT", null, ""));
    } else if (indent < currentIndent) {
      while (this.indentStack.length > 1 && 
             this.indentStack[this.indentStack.length - 1]! > indent) {
        this.indentStack.pop();
        this.tokens.push(this.makeToken("DEDENT", null, ""));
      }
      // Check for inconsistent indentation
      if (this.indentStack[this.indentStack.length - 1] !== indent) {
        const err = LexerErrors.inconsistentIndentation(this.indentStack[this.indentStack.length - 1]!, indent);
        throw new LexerError(err.message, this.currentLoc(), err.hint);
      }
    }
  }

  private handleNewline(): void {
    // Don't emit NEWLINE if the previous token was already NEWLINE or INDENT
    const lastToken = this.tokens[this.tokens.length - 1];
    if (!lastToken || (lastToken.type !== "NEWLINE" && lastToken.type !== "INDENT")) {
      this.tokens.push(this.makeToken("NEWLINE", null, "\n"));
    }
    this.advance(); // consume \n
    this.line++;
    this.column = 1;
    this.atLineStart = true;
  }

  private skipComment(): void {
    this.advance(); // skip first /
    this.advance(); // skip second /
    
    // Capture comment text
    const commentStart = this.pos;
    while (!this.isAtEnd() && this.peek() !== "\n") {
      this.advance();
    }
    const commentText = this.source.slice(commentStart, this.pos).trim();
    
    // Accumulate consecutive comments
    if (this.pendingComment && this.line === this.pendingCommentLine + 1) {
      this.pendingComment += "\n" + commentText;
    } else {
      this.pendingComment = commentText;
    }
    this.pendingCommentLine = this.line;
  }

  private scanString(): void {
    const startLoc = this.currentLoc();
    const startPos = this.pos;
    
    // Check for multiline string """
    if (this.peek() === '"' && this.peekNext() === '"' && this.peekAt(2) === '"') {
      this.scanMultilineString();
      return;
    }

    this.advance(); // consume opening "
    let value = "";
    let hasInterpolation = false;

    while (!this.isAtEnd() && this.peek() !== '"') {
      if (this.peek() === "\n") {
        const err = LexerErrors.unterminatedString();
        throw new LexerError(err.message, startLoc, err.hint);
      }

      if (this.peek() === "\\") {
        value += this.scanEscapeSequence();
      } else if (this.peek() === "{") {
        // For now, just include { literally - interpolation handled at parse time
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

    this.advance(); // consume closing "
    const raw = this.source.slice(startPos, this.pos);
    this.tokens.push(this.makeToken("STRING", value, raw, startLoc));
  }

  private scanMultilineString(): void {
    const startLoc = this.currentLoc();
    const startPos = this.pos;

    this.advance(); // "
    this.advance(); // "
    this.advance(); // "

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

      if (this.peek() === "\n") {
        value += "\n";
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

  private scanRawString(): void {
    const startLoc = this.currentLoc();
    const startPos = this.pos;

    this.advance(); // r

    // Check for multiline raw string r"""
    if (this.peek() === '"' && this.peekNext() === '"' && this.peekAt(2) === '"') {
      this.advance(); // "
      this.advance(); // "
      this.advance(); // "

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

        if (this.peek() === "\n") {
          value += "\n";
          this.advance();
          this.line++;
          this.column = 1;
        } else {
          value += this.advance();
        }
      }
      const err = LexerErrors.unterminatedRawMultilineString();
      throw new LexerError(err.message, startLoc, err.hint);
    }

    this.advance(); // opening "
    let value = "";

    while (!this.isAtEnd() && this.peek() !== '"') {
      if (this.peek() === "\n") {
        const err = LexerErrors.unterminatedRawString();
        throw new LexerError(err.message, startLoc, err.hint);
      }
      value += this.advance();
    }

    if (this.isAtEnd()) {
      const err = LexerErrors.unterminatedRawString();
      throw new LexerError(err.message, startLoc, err.hint);
    }

    this.advance(); // closing "
    const raw = this.source.slice(startPos, this.pos);
    this.tokens.push(this.makeToken("STRING", value, raw, startLoc));
  }

  private scanByteString(): void {
    const startLoc = this.currentLoc();
    const startPos = this.pos;

    this.advance(); // b
    this.advance(); // opening "

    let value = "";
    while (!this.isAtEnd() && this.peek() !== '"') {
      if (this.peek() === "\n") {
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

    this.advance(); // closing "
    const raw = this.source.slice(startPos, this.pos);
    this.tokens.push(this.makeToken("STRING", value, raw, startLoc));
  }

  private scanEscapeSequence(): string {
    this.advance(); // consume backslash
    const char = this.advance();
    switch (char) {
      case "n": return "\n";
      case "t": return "\t";
      case "r": return "\r";
      case "\\": return "\\";
      case '"': return '"';
      case "{": return "{";
      case "}": return "}";
      case "u": {
        // Unicode escape \u#### or \u{######}
        if (this.peek() === "{") {
          this.advance();
          let hex = "";
          while (this.peek() !== "}" && !this.isAtEnd()) {
            hex += this.advance();
          }
          this.advance(); // consume }
          return String.fromCodePoint(parseInt(hex, 16));
        } else {
          let hex = "";
          for (let i = 0; i < 4 && !this.isAtEnd(); i++) {
            hex += this.advance();
          }
          return String.fromCharCode(parseInt(hex, 16));
        }
      }
      case "x": {
        // Hex escape \x##
        let hex = "";
        for (let i = 0; i < 2 && !this.isAtEnd(); i++) {
          hex += this.advance();
        }
        return String.fromCharCode(parseInt(hex, 16));
      }
      default:
        const err = LexerErrors.invalidEscapeSequence(char);
        throw new LexerError(err.message, this.currentLoc(), err.hint);
    }
  }

  private scanNumber(): void {
    const startLoc = this.currentLoc();
    const startPos = this.pos;

    // Check for hex or binary
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

    // Decimal number
    while (this.isDigit(this.peek()) || this.peek() === "_") {
      this.advance();
    }

    // Decimal part
    if (this.peek() === "." && this.isDigit(this.peekNext())) {
      this.advance(); // consume .
      while (this.isDigit(this.peek()) || this.peek() === "_") {
        this.advance();
      }
    }

    // Exponent
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

  private scanHexNumber(startLoc: SourceLocation, startPos: number): void {
    this.advance(); // 0
    this.advance(); // x

    while (this.isHexDigit(this.peek()) || this.peek() === "_") {
      this.advance();
    }

    const raw = this.source.slice(startPos, this.pos);
    const hexPart = raw.slice(2).replace(/_/g, "");
    const value = parseInt(hexPart, 16);
    this.tokens.push(this.makeToken("NUMBER", value, raw, startLoc));
  }

  private scanBinaryNumber(startLoc: SourceLocation, startPos: number): void {
    this.advance(); // 0
    this.advance(); // b

    while (this.peek() === "0" || this.peek() === "1" || this.peek() === "_") {
      this.advance();
    }

    const raw = this.source.slice(startPos, this.pos);
    const binPart = raw.slice(2).replace(/_/g, "");
    const value = parseInt(binPart, 2);
    this.tokens.push(this.makeToken("NUMBER", value, raw, startLoc));
  }

  private scanIdentifier(): void {
    const startLoc = this.currentLoc();
    const startPos = this.pos;

    while (this.isAlphaNumeric(this.peek())) {
      this.advance();
    }

    const raw = this.source.slice(startPos, this.pos);
    const type = KEYWORDS[raw] ?? "IDENTIFIER";
    const value = type === "TRUE" ? true : type === "FALSE" ? false : type === "NULL" ? null : raw;
    this.tokens.push(this.makeToken(type, value, raw, startLoc));
  }

  private scanOperator(): void {
    const startLoc = this.currentLoc();
    const char = this.advance();

    let type: TokenType;
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

  // Helper methods

  private peek(): string {
    if (this.isAtEnd()) return "\0";
    return this.source[this.pos]!;
  }

  private peekNext(): string {
    if (this.pos + 1 >= this.source.length) return "\0";
    return this.source[this.pos + 1]!;
  }

  private peekAt(offset: number): string {
    if (this.pos + offset >= this.source.length) return "\0";
    return this.source[this.pos + offset]!;
  }

  private advance(): string {
    const char = this.source[this.pos]!;
    this.pos++;
    this.column++;
    return char;
  }

  private match(expected: string): boolean {
    if (this.isAtEnd()) return false;
    if (this.source[this.pos] !== expected) return false;
    this.pos++;
    this.column++;
    return true;
  }

  private isAtEnd(): boolean {
    return this.pos >= this.source.length;
  }

  private isDigit(char: string): boolean {
    return char >= "0" && char <= "9";
  }

  private isHexDigit(char: string): boolean {
    return (char >= "0" && char <= "9") ||
           (char >= "a" && char <= "f") ||
           (char >= "A" && char <= "F");
  }

  private isAlpha(char: string): boolean {
    return (char >= "a" && char <= "z") ||
           (char >= "A" && char <= "Z") ||
           char === "_";
  }

  private isAlphaNumeric(char: string): boolean {
    return this.isAlpha(char) || this.isDigit(char);
  }

  private currentLoc(): SourceLocation {
    return { line: this.line, column: this.column, offset: this.pos };
  }

  private makeToken(type: TokenType, value: any, raw: string, loc?: SourceLocation): Token {
    const token: Token = { type, value, raw, loc: loc ?? this.currentLoc() };
    
    // Attach pending comment to meaningful tokens (not whitespace/structure)
    if (this.pendingComment && type !== "NEWLINE" && type !== "INDENT" && type !== "DEDENT" && type !== "EOF") {
      // Only attach if comment is on line immediately before this token
      if ((loc?.line ?? this.line) - this.pendingCommentLine <= 1) {
        token.leadingComment = this.pendingComment;
      }
      this.pendingComment = undefined;
    }
    
    return token;
  }
}
