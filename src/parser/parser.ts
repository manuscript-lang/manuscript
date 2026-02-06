import { Lexer, KEYWORDS } from "../lexer";
import type { Token, TokenType } from "../lexer";

const KEYWORD_TOKEN_TYPES = new Set(KEYWORDS.values());
import * as AST from "./ast";
import { ParserErrors } from "../shared/errors";

export class ParseError extends Error {
  constructor(
    message: string,
    public token: Token,
    public hint?: string
  ) {
    super(`${message} at line ${token.loc.line}, column ${token.loc.column}`);
    this.name = "ParseError";
  }
}

// Operator precedence levels (higher = tighter binding)
const enum Precedence {
  NONE = 0,
  ASSIGNMENT = 1,  // = += -= *= /= %=
  PIPE = 2,        // |
  NULLISH = 3,     // ??
  OR = 4,          // or
  AND = 5,         // and
  NOT = 6,         // not (prefix)
  COMPARISON = 7,  // == != < > <= >= is as
  RANGE = 8,       // ..
  TERM = 9,        // + -
  FACTOR = 10,     // * / %
  POWER = 11,      // ^
  UNARY = 12,      // - not
  CALL = 13,       // () [] . ?. !
}

type PrefixParseFn = () => AST.Expr;
type InfixParseFn = (left: AST.Expr) => AST.Expr;

export class Parser {
  private tokens: Token[] = [];
  private pos: number = 0;

  private prefixParsers: Map<TokenType, PrefixParseFn> = new Map();
  private infixParsers: Map<TokenType, InfixParseFn> = new Map();
  private precedences: Map<TokenType, Precedence> = new Map();

  constructor(source: string) {
    this.tokens = new Lexer(source).tokenize();
    this.registerParsers();
  }

  private registerParsers(): void {
    // Prefix parsers (start of expression)
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

    // Infix parsers (middle of expression)
    this.infix("PLUS", Precedence.TERM, (l) => this.binary(l));
    this.infix("MINUS", Precedence.TERM, (l) => this.binary(l));
    this.infix("STAR", Precedence.FACTOR, (l) => this.binary(l));
    this.infix("SLASH", Precedence.FACTOR, (l) => this.binary(l));
    this.infix("PERCENT", Precedence.FACTOR, (l) => this.binary(l));
    this.infix("CARET", Precedence.POWER, (l) => this.binaryRight(l));
    this.infix("EQ", Precedence.COMPARISON, (l) => this.binary(l));
    this.infix("NEQ", Precedence.COMPARISON, (l) => this.binary(l));
    this.infix("LT", Precedence.COMPARISON, (l) => this.binary(l));
    this.infix("GT", Precedence.COMPARISON, (l) => this.binary(l));
    this.infix("LTE", Precedence.COMPARISON, (l) => this.binary(l));
    this.infix("GTE", Precedence.COMPARISON, (l) => this.binary(l));
    this.infix("AND", Precedence.AND, (l) => this.binary(l));
    this.infix("OR", Precedence.OR, (l) => this.binary(l));
    this.infix("IS", Precedence.COMPARISON, (l) => this.isExpr(l));
    this.infix("AS", Precedence.COMPARISON, (l) => this.asExpr(l));
    this.infix("NULLISH", Precedence.NULLISH, (l) => this.binary(l));
    this.infix("PIPE", Precedence.PIPE, (l) => this.pipeExpr(l));
    this.infix("DOTDOT", Precedence.RANGE, (l) => this.rangeExpr(l));
    this.infix("LPAREN", Precedence.CALL, (l) => this.callExpr(l));
    this.infix("LBRACKET", Precedence.CALL, (l) => this.indexExpr(l, false));
    this.infix("DOT", Precedence.CALL, (l) => this.memberExpr(l, false));
    this.infix("OPTIONAL", Precedence.CALL, (l) => {
      if (this.check("LBRACKET")) {
        this.advance();
        return this.indexExpr(l, true);
      }
      return this.memberExpr(l, true);
    });
    this.infix("BANG", Precedence.CALL, (l) => this.nullAssertion(l));
  }

  private prefix(type: TokenType, fn: PrefixParseFn): void {
    this.prefixParsers.set(type, fn.bind(this));
  }

  private infix(type: TokenType, prec: Precedence, fn: InfixParseFn): void {
    this.precedences.set(type, prec);
    this.infixParsers.set(type, fn.bind(this));
  }

  // ============================================
  // Main entry points
  // ============================================

  parse(): AST.Program {
    const body: AST.Statement[] = [];
    this.skipNewlines();

    while (!this.isAtEnd()) {
      body.push(this.declaration());
      this.skipNewlines();
      // After a multiline with, we may have extra DEDENTs (continuation indent closing)
      while (this.match("DEDENT")) {}
    }

    return {
      kind: "Program",
      body,
      loc: body[0]?.loc ?? { line: 1, column: 1, offset: 0 },
    };
  }

  parseExpression(): AST.Expr {
    this.skipNewlines();
    return this.expression();
  }

  parseStatement(): AST.Statement {
    this.skipNewlines();
    return this.statement();
  }

  // ============================================
  // Declarations
  // ============================================

  private declaration(): AST.Statement {
    const token = this.peek();

    switch (token.type) {
      case "IMPORT":
        return this.importDecl();
      case "FN":
        return this.fnDecl();
      case "EXTERN":
        if (this.peekNext().type === "TYPE") {
          const externDoc = this.current().leadingComment;
          this.advance(); // consume EXTERN
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

  private importDecl(): AST.ImportDecl {
    const loc = this.current().loc;
    this.expect("IMPORT");

    this.expect("LBRACE");
    const names: { name: string; alias?: string }[] = [];

    while (!this.check("RBRACE")) {
      const name = this.expectIdentifier();
      let alias: string | undefined;
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

  private fnDecl(): AST.FnDecl {
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

    // Check if body contains yield (generators are detected automatically)
    const isGenerator = this.containsYield(body);

    return { kind: "FnDecl", name, typeParams, params, returnType, using, body, isGenerator, loc, doc };
  }

  private externFnDecl(): AST.ExternFnDecl {
    const doc = this.current().leadingComment;
    const loc = this.current().loc;
    this.expect("EXTERN");
    this.expect("FN");

    // Allow keywords as extern function names (e.g., spawn, typeof)
    const name = this.expectIdentifierOrKeyword();
    const typeParams = this.check("LBRACKET") ? this.parseTypeParams() : undefined;
    const params = this.parseParams();
    const returnType = this.match("COLON") ? this.parseType() : undefined;

    return { kind: "ExternFnDecl", name, typeParams, params, returnType, loc, doc };
  }

  private expectIdentifierOrKeyword(): string {
    const token = this.advance();
    if (token.type === "IDENTIFIER" || token.value !== null && typeof token.value === "string") {
      return token.raw;
    }
    const err = ParserErrors.expectedToken("IDENTIFIER", token.type);
    throw new ParseError(err.message, token, err.hint);
  }

  private parseParams(): AST.Parameter[] {
    this.expect("LPAREN");
    const params: AST.Parameter[] = [];

    while (!this.check("RPAREN")) {
      const paramLoc = this.current().loc;
      let rest = false;

      if (this.match("SPREAD")) {
        rest = true;
      }

      const name = this.expectIdentifier();
      let optional = false;
      let type: AST.TypeExpr | undefined;
      let defaultValue: AST.Expr | undefined;

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

  private parseUsing(): AST.UsingClause {
    const loc = this.current().loc;
    this.expect("USING");
    this.expect("LPAREN");

    const bindings: AST.UsingBinding[] = [];

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

  private typeDecl(isExtern = false, externDoc?: string): AST.TypeDecl {
    const doc = externDoc ?? this.current().leadingComment;
    const loc = this.current().loc;
    this.expect("TYPE");

    const name = this.expectIdentifier();
    const typeParams = this.check("LBRACKET") ? this.parseTypeParams() : undefined;

    // Check for type alias: type Foo = ...
    if (this.match("ASSIGN")) {
      // Handle union types: type Message = A or B or C
      const firstType = this.parseType();
      if (this.check("OR")) {
        const types: AST.TypeExpr[] = [firstType];
        while (this.match("OR")) {
          types.push(this.parseType());
        }
        // Return as a type alias with union
        return {
          kind: "TypeDecl",
          name,
          typeParams,
          body: { kind: "TypeBody", members: [], loc },
          loc,
          alias: types,
          doc,
        };
      }
      // Simple alias
      return {
        kind: "TypeDecl",
        name,
        typeParams,
        alias: [firstType],
        body: { kind: "TypeBody", members: [], loc },
        loc,
        doc,
      };
    }

    const using = this.check("USING") ? this.parseUsing() : undefined;

    let where: AST.WhereClause[] | undefined;
    if (this.check("WHERE")) {
      where = this.parseWhere();
    }

    // Body is optional for extern types (can be empty)
    let body: AST.TypeBody;
    if (this.match("NEWLINE") && this.check("INDENT")) {
      body = this.parseTypeBody(isExtern);
    } else {
      body = { kind: "TypeBody", members: [], loc };
    }

    return { kind: "TypeDecl", name, typeParams, using, where, body, loc, isExtern: isExtern || undefined, doc };
  }

  private interfaceDecl(): AST.InterfaceDecl {
    const doc = this.current().leadingComment;
    const loc = this.current().loc;
    this.expect("INTERFACE");
    const name = this.expectIdentifier();
    const typeParams = this.check("LBRACKET") ? this.parseTypeParams() : undefined;
    let body: AST.InterfaceBody;
    if (this.match("NEWLINE") && this.check("INDENT")) {
      body = this.parseInterfaceBody();
    } else {
      body = { kind: "InterfaceBody", members: [], loc: this.current().loc };
    }
    return { kind: "InterfaceDecl", name, typeParams, body, loc, doc };
  }

  private parseInterfaceBody(): AST.InterfaceBody {
    const loc = this.current().loc;
    const members: AST.InterfaceMember[] = [];
    this.expect("INDENT");
    this.skipNewlines();
    while (!this.check("DEDENT") && !this.isAtEnd()) {
      if (this.check("FN") || this.check("EXTERN")) {
        members.push(this.parseMethodDecl(false, true));
      } else if (this.isEmbeddedType()) {
        members.push(this.parseEmbeddedInterface());
      } else {
        const name = this.peek().value as string;
        throw new ParseError(
          `Unexpected token in interface body: expected method signature or embedded interface name, got '${name}'`,
          this.current(),
          "Interfaces contain only fn signatures and embedded interface names"
        );
      }
      this.skipNewlines();
    }
    this.expect("DEDENT");
    return { kind: "InterfaceBody", members, loc };
  }

  private parseEmbeddedInterface(): AST.EmbeddedInterfaceDecl {
    const loc = this.current().loc;
    const name = this.expectIdentifier();
    return { kind: "EmbeddedInterfaceDecl", name, loc };
  }

  private parseTypeParams(): AST.TypeParam[] {
    this.expect("LBRACKET");
    const params: AST.TypeParam[] = [];

    while (!this.check("RBRACKET")) {
      const paramLoc = this.current().loc;
      const name = this.expectIdentifier();
      let constraint: AST.TypeExpr | undefined;

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

  private parseWhere(): AST.WhereClause[] {
    const clauses: AST.WhereClause[] = [];
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

  private parseTypeBody(isExternType = false): AST.TypeBody {
    const loc = this.current().loc;
    const members: AST.TypeMember[] = [];

    this.expect("INDENT");
    this.skipNewlines();

    while (!this.check("DEDENT") && !this.isAtEnd()) {
      if (this.check("FN") || this.check("EXTERN")) {
        // Parse method - isExternType makes all methods implicitly extern
        members.push(this.parseMethodDecl(isExternType));
      } else if (this.isEmbeddedType()) {
        // Go-style embedding: capitalized type name without colon
        members.push(this.parseEmbeddedType());
      } else {
        members.push(this.parseFieldDecl());
      }
      this.skipNewlines();
    }

    this.expect("DEDENT");
    return { kind: "TypeBody", members, loc };
  }

  private parseFieldDecl(): AST.FieldDecl {
    const doc = this.current().leadingComment;
    const loc = this.current().loc;
    const name = this.expectIdentifier();

    let optional = false;
    if (this.match("QUESTION")) {
      optional = true;
    }

    let type: AST.TypeExpr | undefined;
    if (this.match("COLON")) {
      // Check for computed field: name: () => expr (store as LambdaExpr so it's a method)
      if (this.check("LPAREN")) {
        const next = this.peekNext();
        if (next.type === "RPAREN") {
          this.advance(); // (
          this.advance(); // )
          this.expect("ARROW");
          const body = this.expression();
          const lambda: AST.LambdaExpr = { kind: "LambdaExpr", params: [], body, loc };
          return { kind: "FieldDecl", name, optional, computed: true, defaultValue: lambda, loc, doc };
        }
      }
      type = this.parseType();
    }

    let defaultValue: AST.Expr | undefined;
    if (this.match("ASSIGN")) {
      defaultValue = this.expression();
    }

    return { kind: "FieldDecl", name, type, optional, defaultValue, computed: false, loc, doc };
  }

  // Check if current position is an embedded type (Go-style embedding)
  // Embedded type: Capitalized identifier NOT followed by : or ?
  private isEmbeddedType(): boolean {
    if (!this.check("IDENTIFIER")) return false;
    const name = this.peek().value as string;
    // Must be capitalized (first char is uppercase letter)
    if (!name || name.length === 0) return false;
    const firstChar = name[0]!;
    if (firstChar !== firstChar.toUpperCase() || firstChar === firstChar.toLowerCase()) {
      return false;
    }
    // Must NOT be followed by : or ? (which would make it a regular field)
    const next = this.peekNext();
    return next.type !== "COLON" && next.type !== "QUESTION";
  }

  // Parse Go-style embedded type
  private parseEmbeddedType(): AST.FieldDecl {
    const loc = this.current().loc;
    const name = this.expectIdentifier();
    return {
      kind: "FieldDecl",
      name,
      type: { kind: "NamedType", name, loc },
      optional: false,
      computed: false,
      embedded: true,
      loc,
    };
  }

  private parseMethodDecl(implicitExtern = false, skipBody = false): AST.MethodDecl {
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

    let body: AST.Block | undefined;
    if (!skipBody && !isExtern && this.match("NEWLINE") && this.check("INDENT")) {
      body = this.parseBlock();
    }

    return { kind: "MethodDecl", name, typeParams, params, returnType, using, body, isExtern: isExtern || undefined, loc, doc };
  }

  private testDecl(): AST.TestDecl {
    const loc = this.current().loc;
    this.expect("TEST");

    const description = this.expectString();

    let withClause: AST.Expr | undefined;
    if (this.match("WITH")) {
      withClause = this.expression();
    }

    this.expectNewline();
    const body = this.parseBlock();

    return { kind: "TestDecl", description, withClause, body, loc };
  }

  // ============================================
  // Statements
  // ============================================

  private statement(): AST.Statement {
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

  private letStmt(): AST.LetStmt {
    const loc = this.current().loc;
    this.expect("LET");

    const pattern = this.parsePattern();
    const type = this.match("COLON") ? this.parseType() : undefined;
    this.expect("ASSIGN");
    const value = this.expression();

    return { kind: "LetStmt", pattern, type, value, loc };
  }

  private varStmt(): AST.VarStmt {
    const loc = this.current().loc;
    this.expect("VAR");

    const name = this.expectIdentifier();
    const type = this.match("COLON") ? this.parseType() : undefined;
    this.expect("ASSIGN");
    const value = this.expression();

    return { kind: "VarStmt", name, type, value, loc };
  }

  private ifStmt(): AST.IfStmt | AST.ExprStmt {
    const loc = this.current().loc;
    this.expect("IF");

    // Check for guard form: if let pattern = expr else return
    if (this.check("LET")) {
      return this.guardStmt(loc);
    }

    const condition = this.expression();

    // Inline form: if cond then stmt/expr
    if (this.match("THEN")) {
      // Check if next token starts a statement keyword
      const isStatement = this.check("RETURN") || this.check("BREAK") || 
                         this.check("CONTINUE") || this.check("THROW") ||
                         this.check("LET") || this.check("VAR");
      
      if (isStatement) {
        // Parse as statement
        const then = this.statement();
        return { kind: "IfStmt", condition, then, elseIfs: [], loc };
      }
      
      // Parse as expression
      const thenExpr = this.expression();
      
      // If followed by else, this is an if expression (not statement)
      if (this.check("ELSE")) {
        this.advance(); // consume ELSE
        const elseExpr = this.expression();
        const ifExpr: AST.IfExpr = {
          kind: "IfExpr",
          condition,
          then: thenExpr,
          else: elseExpr,
          loc,
        };
        return { kind: "ExprStmt", expr: ifExpr, loc };
      }
      
      // Otherwise it's an inline if statement with expression
      const then: AST.ExprStmt = { kind: "ExprStmt", expr: thenExpr, loc: thenExpr.loc };
      return { kind: "IfStmt", condition, then, elseIfs: [], loc };
    }

    this.expectNewline();
    const then = this.parseBlock();

    const elseIfs: { condition: AST.Expr; body: AST.Block }[] = [];
    let elseBlock: AST.Block | undefined;

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

  private guardStmt(loc: AST.SourceLocation): AST.IfStmt {
    this.expect("LET");
    const pattern = this.parsePattern();
    this.expect("ASSIGN");
    const condition = this.expression();
    this.expect("ELSE");
    // The else part can be return, throw, or an expression
    let elseReturn: AST.Expr;
    if (this.check("RETURN") || this.check("THROW")) {
      // Parse as statement but extract the value
      const stmtKind = this.peek().type;
      this.advance();
      elseReturn = this.check("NEWLINE") || this.check("EOF") 
        ? { kind: "Identifier", name: "null", loc } as AST.Identifier
        : this.expression();
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
      loc,
    };
  }

  private forStmt(): AST.ForStmt {
    const loc = this.current().loc;
    this.expect("FOR");

    // Check for infinite loop: for \n body
    if (this.check("NEWLINE")) {
      this.advance(); // consume newline
      const body = this.parseBlock();
      return { kind: "ForStmt", body, loc };
    }

    const pattern = this.parsePattern();
    this.expect("IN");
    const iterable = this.expression();
    this.expectNewline();
    const body = this.parseBlock();

    return { kind: "ForStmt", pattern, iterable, body, loc };
  }

  private matchStmt(): AST.MatchStmt {
    const loc = this.current().loc;
    this.expect("MATCH");

    const value = this.expression();
    this.expectNewline();
    this.expect("INDENT");
    this.skipNewlines();

    const arms: AST.MatchArm[] = [];
    while (!this.check("DEDENT") && !this.isAtEnd()) {
      arms.push(this.parseMatchArm());
      this.skipNewlines();
    }

    this.expect("DEDENT");
    return { kind: "MatchStmt", value, arms, loc };
  }

  private parseMatchArm(): AST.MatchArm {
    const loc = this.current().loc;
    const pattern = this.parsePattern();

    let guard: AST.Expr | undefined;
    if (this.check("IF")) {
      this.advance(); // consume 'if'
      guard = this.parseGuardExpression();
    }

    this.expect("ARROW");
    const body = this.expression();

    return { kind: "MatchArm", pattern, guard, body, loc };
  }

  // Parse guard expression (stops at =>)
  private parseGuardExpression(): AST.Expr {
    return this.expression(Precedence.ASSIGNMENT + 1);
  }

  private returnStmt(): AST.ReturnStmt {
    const loc = this.current().loc;
    this.expect("RETURN");

    let value: AST.Expr | undefined;
    if (!this.check("NEWLINE") && !this.check("DEDENT") && !this.isAtEnd()) {
      value = this.expression();
    }

    return { kind: "ReturnStmt", value, loc };
  }

  private yieldStmt(): AST.YieldStmt {
    const loc = this.current().loc;
    this.expect("YIELD");
    const value = this.expression();
    return { kind: "YieldStmt", value, loc };
  }

  private breakStmt(): AST.BreakStmt {
    const loc = this.current().loc;
    this.expect("BREAK");
    return { kind: "BreakStmt", loc };
  }

  private continueStmt(): AST.ContinueStmt {
    const loc = this.current().loc;
    this.expect("CONTINUE");
    return { kind: "ContinueStmt", loc };
  }

  private deferStmt(): AST.DeferStmt {
    const loc = this.current().loc;
    this.expect("DEFER");
    const body = this.statement();
    return { kind: "DeferStmt", body, loc };
  }

  private tryStmt(): AST.TryStmt {
    const loc = this.current().loc;
    this.expect("TRY");
    this.expectNewline();
    const body = this.parseBlock();

    let catchClause: { name: string; body: AST.Block } | undefined;
    if (this.match("CATCH")) {
      const name = this.expectIdentifier();
      this.expectNewline();
      const catchBody = this.parseBlock();
      catchClause = { name, body: catchBody };
    }

    return { kind: "TryStmt", body, catch: catchClause, loc };
  }

  private throwStmt(): AST.ThrowStmt {
    const loc = this.current().loc;
    this.expect("THROW");
    // throw can be followed by a call or a string directly
    const value = this.expression();
    return { kind: "ThrowStmt", value, loc };
  }

  private withStmt(): AST.WithStmt {
    const loc = this.current().loc;
    this.expect("WITH");
    // First context must follow "with" on same line; newline+indent only allowed after comma

    const contexts: AST.WithContext[] = [];

    do {
      // Allow newline+indent only after comma (e.g. with A(),\n  let b = B()), not after "with"
      if (contexts.length > 0) this.skipBracketedWhitespace();
      // New syntax: with let name = expr OR with expr
      if (this.match("LET")) {
        // with let name = expr (expr may be multiline)
        const name = this.expectIdentifier();
        const nameLoc = this.previous().loc;
        this.expect("ASSIGN");
        this.skipBracketedWhitespace();
        const expr = this.parseContextExpr();
        contexts.push({ expr, name, nameLoc });
      } else {
        // with expr (anonymous, may be multiline)
        const expr = this.parseContextExpr();
        contexts.push({ expr });
      }
    } while (this.match("COMMA"));

    this.expectNewline();
    const body = this.parseBlock();

    return { kind: "WithStmt", contexts, body, loc };
  }

  // Parse context expression - stops at comma or newline
  private parseContextExpr(): AST.Expr {
    // Parse a primary expression followed by calls/member access
    let expr = this.parsePrimaryExpr();
    
    while (true) {
      if (this.check("LPAREN")) {
        this.advance();
        expr = this.finishCallExpr(expr);
      } else if (this.check("DOT")) {
        this.advance();
        const prop = this.expectIdentifier();
        expr = { kind: "MemberExpr", object: expr, property: prop, optional: false, loc: expr.loc } as AST.MemberExpr;
      } else if (this.check("OPTIONAL")) {
        this.advance();
        const prop = this.expectIdentifier();
        expr = { kind: "MemberExpr", object: expr, property: prop, optional: true, loc: expr.loc } as AST.MemberExpr;
      } else {
        break;
      }
    }
    
    return expr;
  }

  private parsePrimaryExpr(): AST.Expr {
    const token = this.peek();
    
    if (token.type === "IDENTIFIER") {
      this.advance();
      return { kind: "Identifier", name: token.value as string, loc: token.loc };
    }
    if (token.type === "STRING") {
      this.advance();
      return { kind: "Literal", value: token.value as string, loc: token.loc };
    }
    if (token.type === "NUMBER") {
      this.advance();
      return { kind: "Literal", value: token.value as number, loc: token.loc };
    }
    
    const err = ParserErrors.unexpectedTokenInContext(token.type);
    throw new ParseError(err.message, token, err.hint);
  }

  private finishCallExpr(callee: AST.Expr): AST.CallExpr {
    const loc = callee.loc;
    const args: (AST.Expr | { name: string; value: AST.Expr })[] = [];

    while (true) {
      this.skipBracketedWhitespace();
      if (this.check("RPAREN")) break;
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

  private exprOrAssignStmt(): AST.Statement {
    const loc = this.current().loc;
    const expr = this.expression();

    // Check for assignment
    if (this.check("ASSIGN") || this.check("PLUS_ASSIGN") || this.check("MINUS_ASSIGN") ||
        this.check("STAR_ASSIGN") || this.check("SLASH_ASSIGN") || this.check("PERCENT_ASSIGN")) {
      const op = this.advance().raw as AST.AssignStmt["op"];
      const value = this.expression();
      return { kind: "AssignStmt", target: expr, op, value, loc };
    }

    return { kind: "ExprStmt", expr, loc };
  }

  // ============================================
  // Blocks
  // ============================================

  private parseBlock(): AST.Block {
    const loc = this.current().loc;
    const statements: AST.Statement[] = [];

    this.expect("INDENT");
    this.skipNewlines();

    while (!this.check("DEDENT") && !this.isAtEnd()) {
      statements.push(this.statement());
      this.skipNewlines();
    }

    this.expect("DEDENT");
    return { kind: "Block", statements, loc };
  }

  // ============================================
  // Expressions (Pratt Parser)
  // ============================================

  private expression(precedence: Precedence = Precedence.NONE): AST.Expr {
    const token = this.advance();
    const prefixParser = this.prefixParsers.get(token.type);

    if (!prefixParser) {
      const err = ParserErrors.unexpectedToken(token.type);
      throw new ParseError(err.message, token, err.hint);
    }

    let left = prefixParser();

    while (precedence < this.currentPrecedence() || this.tryLineContinuation(precedence)) {
      const infixParser = this.infixParsers.get(this.peek().type);
      if (!infixParser) break;
      this.advance();
      left = infixParser(left);
    }

    return left;
  }

  // Operators that can trigger line continuation
  private static LINE_CONTINUATION_OPS = new Set<TokenType>([
    "PIPE", "PLUS", "MINUS", "STAR", "SLASH", "PERCENT", "CARET",
    "AND", "OR", "EQ", "NEQ", "LT", "GT", "LTE", "GTE",
    "NULLISH", "DOTDOT"
  ]);

  // Check if expression can continue on next line and consume whitespace if so
  // Only allows continuation without indentation changes and only for binary operators
  private tryLineContinuation(precedence: Precedence): boolean {
    if (!this.check("NEWLINE")) return false;
    
    // Save position to peek ahead
    const savedPos = this.pos;
    
    // Skip only newlines (not INDENT/DEDENT)
    while (this.match("NEWLINE")) {}
    
    // If we hit INDENT or DEDENT, this is not a simple line continuation
    if (this.check("INDENT") || this.check("DEDENT")) {
      this.pos = savedPos;
      return false;
    }
    
    // Only continue for specific binary operators, not for calls/members/etc.
    const nextToken = this.peek().type;
    if (!Parser.LINE_CONTINUATION_OPS.has(nextToken)) {
      this.pos = savedPos;
      return false;
    }
    
    // Check if next token has higher precedence
    const nextPrec = this.precedences.get(nextToken) ?? Precedence.NONE;
    const canContinue = nextPrec > precedence;
    
    if (!canContinue) {
      // Restore position if we can't continue
      this.pos = savedPos;
    }
    
    return canContinue;
  }

  private currentPrecedence(): Precedence {
    return this.precedences.get(this.peek().type) ?? Precedence.NONE;
  }

  private literal(): AST.Literal | AST.TemplateLiteral {
    const token = this.previous();
    
    // Check if this is a string with template interpolations
    if (token.type === "STRING" && typeof token.value === "string") {
      const str = token.value as string;
      // Check for {identifier} or {expr} patterns (but not escaped braces)
      if (str.includes("{") && str.includes("}")) {
        return this.parseTemplateString(str, token.loc);
      }
    }
    
    return {
      kind: "Literal",
      value: token.value as number | string | boolean | null,
      loc: token.loc,
    };
  }
  
  private parseTemplateString(str: string, loc: AST.SourceLocation): AST.TemplateLiteral {
    const parts: (string | AST.TemplateExpr)[] = [];
    let currentText = "";
    let i = 0;
    
    while (i < str.length) {
      if (str[i] === "{") {
        // Found start of interpolation
        if (currentText) {
          parts.push(currentText);
          currentText = "";
        }
        
        // Find the matching closing brace
        let depth = 1;
        let exprStart = i + 1;
        i++;
        
        while (i < str.length && depth > 0) {
          if (str[i] === "{") depth++;
          else if (str[i] === "}") depth--;
          i++;
        }
        
        const exprStr = str.slice(exprStart, i - 1);
        const exprParts = exprStr.trim();
        
        // Compute location for the expression inside braces
        // +1 for opening quote, +exprStart for position within string
        const exprLoc: AST.SourceLocation = {
          line: loc.line,
          column: loc.column + 1 + exprStart,
          offset: loc.offset + 1 + exprStart,
        };
        
        if (/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(exprParts)) {
          // Simple identifier
          parts.push({
            kind: "TemplateExpr",
            expr: { kind: "Identifier", name: exprParts, loc: exprLoc },
            loc: exprLoc,
          });
        } else {
          // Complex expression - recursively parse
          try {
            const parser = new Parser(exprParts);
            const program = parser.parse();
            if (program.body.length === 1 && program.body[0]?.kind === "ExprStmt") {
              // Adjust locations for the parsed expression
              const expr = (program.body[0] as AST.ExprStmt).expr;
              this.adjustExprLocations(expr, exprLoc);
              parts.push({
                kind: "TemplateExpr",
                expr,
                loc: exprLoc,
              });
            }
          } catch {
            // Fall back to treating as text if parse fails
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
  
  private adjustExprLocations(expr: AST.Expr, baseLoc: AST.SourceLocation): void {
    // Adjust the expression's location relative to the base
    expr.loc = {
      line: baseLoc.line,
      column: baseLoc.column + expr.loc.column - 1,
      offset: baseLoc.offset + expr.loc.offset,
    };
    // Recursively adjust nested expressions
    if (expr.kind === "MemberExpr") {
      this.adjustExprLocations(expr.object, baseLoc);
    } else if (expr.kind === "CallExpr") {
      this.adjustExprLocations(expr.callee, baseLoc);
      for (const arg of expr.args) {
        if ("kind" in arg) this.adjustExprLocations(arg, baseLoc);
      }
    } else if (expr.kind === "BinaryExpr") {
      this.adjustExprLocations(expr.left, baseLoc);
      this.adjustExprLocations(expr.right, baseLoc);
    } else if (expr.kind === "IndexExpr") {
      this.adjustExprLocations(expr.object, baseLoc);
      this.adjustExprLocations(expr.index, baseLoc);
    }
  }

  private identifier(): AST.Identifier {
    const token = this.previous();
    return {
      kind: "Identifier",
      name: token.value as string,
      loc: token.loc,
    };
  }

  private groupOrLambda(): AST.Expr {
    const loc = this.previous().loc;

    // Check for empty lambda: () => ...
    if (this.check("RPAREN")) {
      this.advance();
      if (this.match("ARROW")) {
        return this.parseLambdaBody([], loc);
      }
      const err = ParserErrors.emptyParentheses();
      throw new ParseError(err.message, this.current(), err.hint);
    }

    // Parse first expression
    const first = this.expression();

    // Check for comma (lambda with multiple params or tuple)
    if (this.check("COMMA") || (first.kind === "Identifier" && this.check("COLON"))) {
      // This is a lambda parameter list
      return this.parseLambdaFromFirst(first, loc);
    }

    this.expect("RPAREN");

    // Check for arrow (single-param lambda)
    if (this.match("ARROW")) {
      if (first.kind !== "Identifier") {
        const err = ParserErrors.lambdaParamMustBeIdentifier();
        throw new ParseError(err.message, this.current(), err.hint);
      }
      const params: AST.Parameter[] = [{
        kind: "Parameter",
        name: first.name,
        optional: false,
        rest: false,
        loc: first.loc,
      }];
      return this.parseLambdaBody(params, loc);
    }

    // Just a grouped expression
    return first;
  }

  private parseLambdaFromFirst(first: AST.Expr, loc: AST.SourceLocation): AST.LambdaExpr {
    const params: AST.Parameter[] = [];

    // Parse first parameter
    if (first.kind !== "Identifier") {
      const err = ParserErrors.lambdaParamMustBeIdentifier();
      throw new ParseError(err.message, this.current(), err.hint);
    }
    let type: AST.TypeExpr | undefined;
    if (this.match("COLON")) {
      type = this.parseType();
    }
    params.push({ kind: "Parameter", name: first.name, type, optional: false, rest: false, loc: first.loc });

    // Parse remaining parameters
    while (this.match("COMMA")) {
      const paramLoc = this.current().loc;
      const name = this.expectIdentifier();
      let paramType: AST.TypeExpr | undefined;
      if (this.match("COLON")) {
        paramType = this.parseType();
      }
      params.push({ kind: "Parameter", name, type: paramType, optional: false, rest: false, loc: paramLoc });
    }

    this.expect("RPAREN");
    this.expect("ARROW");

    return this.parseLambdaBody(params, loc);
  }

  private parseLambdaBody(params: AST.Parameter[], loc: AST.SourceLocation): AST.LambdaExpr {
    const body = this.expression();
    return { kind: "LambdaExpr", params, body, loc };
  }

  private listExpr(): AST.ListExpr {
    const loc = this.previous().loc;
    const elements: (AST.Expr | AST.SpreadElement)[] = [];

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

  private setExpr(): AST.SetExpr {
    const loc = this.previous().loc;
    const elements: AST.Expr[] = [];
    this.skipBracketedWhitespace();
    if (this.check("GT")) {
      this.advance();
      return { kind: "SetExpr", elements, loc };
    }
    while (!this.check("GT")) {
      elements.push(this.expression(Precedence.COMPARISON));
      this.skipBracketedWhitespace();
      if (!this.check("GT")) this.expect("COMMA");
      this.skipBracketedWhitespace();
    }
    this.expect("GT");
    return { kind: "SetExpr", elements, loc };
  }

  private mapExpr(): AST.MapExpr {
    const loc = this.previous().loc;
    const entries: AST.MapEntry[] = [];

    this.skipBracketedWhitespace();
    while (!this.check("RBRACE")) {
      const entryLoc = this.current().loc;

      if (this.match("SPREAD")) {
        const expr = this.expression();
        entries.push({ kind: "MapEntry", key: expr, value: expr, spread: true, loc: entryLoc });
      } else if (this.peekNext().type === "COLON" && (this.check("IDENTIFIER") || KEYWORD_TOKEN_TYPES.has(this.peek().type))) {
        const t = this.advance();
        const key: AST.Expr = { kind: "Identifier", name: t.raw, loc: t.loc };
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

  private unary(): AST.UnaryExpr {
    const token = this.previous();
    const operand = this.expression(Precedence.UNARY);
    return { kind: "UnaryExpr", op: token.raw, operand, loc: token.loc };
  }

  private binary(left: AST.Expr): AST.BinaryExpr {
    const token = this.previous();
    const right = this.expression(this.precedences.get(token.type) ?? Precedence.NONE);
    return { kind: "BinaryExpr", op: token.raw, left, right, loc: token.loc };
  }

  private binaryRight(left: AST.Expr): AST.BinaryExpr {
    const token = this.previous();
    // Right associative - use precedence - 1
    const right = this.expression((this.precedences.get(token.type) ?? Precedence.NONE) - 1);
    return { kind: "BinaryExpr", op: token.raw, left, right, loc: token.loc };
  }

  private callExpr(callee: AST.Expr): AST.CallExpr {
    const loc = this.previous().loc;
    const args: (AST.Expr | { name: string; value: AST.Expr })[] = [];

    while (!this.check("RPAREN")) {
      // Check for named argument: name: value
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

  private indexExpr(object: AST.Expr, optional: boolean): AST.IndexExpr {
    const loc = this.previous().loc;

    // Check for slice: [start:end] or [start:end:step]
    if (this.check("COLON")) {
      return this.sliceExpr(object, undefined, loc, optional);
    }

    const index = this.expression();

    if (this.check("COLON")) {
      return this.sliceExpr(object, index, loc, optional);
    }

    // Check for additional type args: Type[A, B, C]
    const typeArgs: AST.Expr[] = [];
    while (this.match("COMMA")) {
      typeArgs.push(this.expression());
    }

    this.expect("RBRACKET");
    
    if (typeArgs.length > 0) {
      return { kind: "IndexExpr", object, index, optional, typeArgs, loc };
    }
    return { kind: "IndexExpr", object, index, optional, loc };
  }

  private sliceExpr(object: AST.Expr, start: AST.Expr | undefined, loc: AST.SourceLocation, optional: boolean): AST.IndexExpr {
    this.expect("COLON");
    let end: AST.Expr | undefined;
    let step: AST.Expr | undefined;

    if (!this.check("COLON") && !this.check("RBRACKET")) {
      end = this.expression();
    }

    if (this.match("COLON")) {
      if (!this.check("RBRACKET")) {
        step = this.expression();
      }
    }

    this.expect("RBRACKET");

    const dummyIndex: AST.Literal = { kind: "Literal", value: 0, loc };
    return {
      kind: "IndexExpr",
      object,
      index: dummyIndex,
      optional,
      slice: { start, end, step },
      loc,
    };
  }

  private memberExpr(object: AST.Expr, optional: boolean): AST.MemberExpr {
    const loc = this.previous().loc;
    const property = this.expectIdentifier();
    return { kind: "MemberExpr", object, property, optional, loc };
  }

  private pipeExpr(left: AST.Expr): AST.PipeExpr {
    const loc = this.previous().loc;
    const right = this.expression(Precedence.PIPE);
    return { kind: "PipeExpr", left, right, loc };
  }

  private rangeExpr(start: AST.Expr): AST.RangeExpr {
    const loc = this.previous().loc;
    const end = this.expression(Precedence.RANGE);
    return { kind: "RangeExpr", start, end, inclusive: false, loc };
  }

  private isExpr(left: AST.Expr): AST.BinaryExpr {
    const loc = this.previous().loc;
    const right = this.parseType();
    return {
      kind: "BinaryExpr",
      op: "is",
      left,
      right: { kind: "Identifier", name: (right as AST.NamedType).name, loc },
      loc,
    };
  }

  private asExpr(expr: AST.Expr): AST.TypeAssertion {
    const loc = this.previous().loc;
    const type = this.parseType();
    return { kind: "TypeAssertion", expr, type, loc };
  }

  private nullAssertion(expr: AST.Expr): AST.NullAssertion {
    const loc = this.previous().loc;
    return { kind: "NullAssertion", expr, loc };
  }

  private ifExpr(): AST.IfExpr {
    const loc = this.previous().loc;
    const condition = this.expression();
    this.expect("THEN");
    const thenExpr = this.expression();
    this.expect("ELSE");
    const elseExpr = this.expression();
    return { kind: "IfExpr", condition, then: thenExpr, else: elseExpr, loc };
  }

  private matchExpr(): AST.MatchExpr {
    // Match as expression - inline arms
    const loc = this.previous().loc;
    const value = this.expression();
    this.expectNewline();
    this.expect("INDENT");
    this.skipNewlines();

    const arms: AST.MatchArm[] = [];
    while (!this.check("DEDENT") && !this.isAtEnd()) {
      arms.push(this.parseMatchArm());
      this.skipNewlines();
    }

    this.expect("DEDENT");
    return { kind: "MatchExpr", value, arms, loc };
  }

  private spawnExpr(): AST.SpawnExpr {
    const loc = this.previous().loc;
    // spawn should parse the following expression which is typically a call
    const expr = this.expression(Precedence.UNARY);
    return { kind: "SpawnExpr", expr, loc };
  }

  // ============================================
  // Patterns
  // ============================================

  private parsePattern(): AST.Pattern {
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
      const value = token.value as number;
      // Check for range pattern
      if (this.match("DOTDOT")) {
        const endToken = this.expect("NUMBER");
        return { kind: "RangePattern", start: value, end: endToken.value as number, loc: token.loc };
      }
      return { kind: "LiteralPattern", value, loc: token.loc };
    }
    if (token.type === "STRING") {
      this.advance();
      return { kind: "LiteralPattern", value: token.value as string, loc: token.loc };
    }
    if (token.type === "TRUE" || token.type === "FALSE") {
      this.advance();
      return { kind: "LiteralPattern", value: token.value as boolean, loc: token.loc };
    }
    if (token.type === "NULL") {
      this.advance();
      return { kind: "LiteralPattern", value: null, loc: token.loc };
    }
    if (token.type === "IDENTIFIER") {
      this.advance();
      const name = token.value as string;
      if (name === "_") {
        return { kind: "WildcardPattern", loc: token.loc };
      }
      // Check for type pattern: Type as binding
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

  private objectPattern(): AST.ObjectPattern {
    const loc = this.current().loc;
    this.expect("LBRACE");

    const properties: { key: string; pattern: AST.Pattern }[] = [];

    while (!this.check("RBRACE")) {
      const key = this.expectIdentifier();
      let pattern: AST.Pattern = { kind: "IdentifierPattern", name: key, loc: this.current().loc };

      // Check for nested pattern: { name: pattern }
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

  private arrayPattern(): AST.ArrayPattern {
    const loc = this.current().loc;
    this.expect("LBRACKET");

    const elements: AST.Pattern[] = [];

    while (!this.check("RBRACKET")) {
      elements.push(this.parsePattern());
      if (!this.check("RBRACKET")) {
        this.expect("COMMA");
      }
    }

    this.expect("RBRACKET");
    return { kind: "ArrayPattern", elements, loc };
  }

  // ============================================
  // Types
  // ============================================

  private parseType(): AST.TypeExpr {
    let type = this.parsePrimaryType();

    // Check for union: T or U
    if (this.check("OR")) {
      const types: AST.TypeExpr[] = [type];
      while (this.match("OR")) {
        types.push(this.parsePrimaryType());
      }
      type = { kind: "UnionType", types, loc: type.loc };
    }

    // Check for optional: T?
    if (this.match("QUESTION")) {
      type = { kind: "OptionalType", inner: type, loc: type.loc };
    }

    return type;
  }

  private parsePrimaryType(): AST.TypeExpr {
    const token = this.peek();

    // Function type: fn(A, B): R
    if (token.type === "FN") {
      return this.parseFunctionType();
    }

    // Named type with potential generics: List[T], Map[K, V]
    // Or type predicate: x is Type
    if (token.type === "IDENTIFIER") {
      this.advance();
      const name = token.value as string;

      // Check for type predicate: x is Type
      if (this.check("IS")) {
        this.advance();
        const targetType = this.parsePrimaryType();
        return { kind: "TypePredicateExpr", paramName: name, targetType, loc: token.loc };
      }

      // Check for generic arguments
      if (this.check("LBRACKET")) {
        this.advance();
        const args: AST.TypeExpr[] = [];
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

    // String literal type: "pending" or "done"
    if (token.type === "STRING") {
      this.advance();
      return { kind: "NamedType", name: `"${token.value}"`, loc: token.loc };
    }

    const err = ParserErrors.expectedType(token.type);
    throw new ParseError(err.message, token, err.hint);
  }

  private parseFunctionType(): AST.FunctionType {
    const loc = this.current().loc;
    this.expect("FN");
    this.expect("LPAREN");

    const params: AST.TypeExpr[] = [];
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

  // ============================================
  // Helpers
  // ============================================

  private containsYield(block: AST.Block): boolean {
    for (const stmt of block.statements) {
      if (stmt.kind === "YieldStmt") return true;
      if (stmt.kind === "IfStmt") {
        if (stmt.then.kind === "Block" && this.containsYield(stmt.then)) return true;
        for (const elif of stmt.elseIfs) {
          if (this.containsYield(elif.body)) return true;
        }
        if (stmt.else && this.containsYield(stmt.else)) return true;
      }
      if (stmt.kind === "ForStmt" && this.containsYield(stmt.body)) return true;
      if (stmt.kind === "TryStmt") {
        if (this.containsYield(stmt.body)) return true;
        if (stmt.catch && this.containsYield(stmt.catch.body)) return true;
      }
    }
    return false;
  }

  private peek(): Token {
    return this.tokens[this.pos] ?? this.tokens[this.tokens.length - 1]!;
  }

  private peekNext(): Token {
    return this.tokens[this.pos + 1] ?? this.tokens[this.tokens.length - 1]!;
  }

  private previous(): Token {
    return this.tokens[this.pos - 1]!;
  }

  private current(): Token {
    return this.tokens[this.pos]!;
  }

  private advance(): Token {
    if (!this.isAtEnd()) this.pos++;
    return this.previous();
  }

  private isAtEnd(): boolean {
    return this.peek().type === "EOF";
  }

  private check(type: TokenType): boolean {
    return this.peek().type === type;
  }

  private match(type: TokenType): boolean {
    if (this.check(type)) {
      this.advance();
      return true;
    }
    return false;
  }

  private expect(type: TokenType): Token {
    if (this.check(type)) {
      return this.advance();
    }
    const err = ParserErrors.expectedToken(type, this.peek().type);
    throw new ParseError(err.message, this.peek(), err.hint);
  }

  private expectIdentifier(): string {
    const token = this.expect("IDENTIFIER");
    return token.value as string;
  }

  private expectName(): string {
    const token = this.current();
    if (token.type === "IDENTIFIER") {
      this.advance();
      return token.value as string;
    }
    const err = ParserErrors.expectedName(token.type);
    throw new ParseError(err.message, token, err.hint);
  }

  private expectString(): string {
    const token = this.expect("STRING");
    return token.value as string;
  }

  private expectNewline(): void {
    if (!this.check("NEWLINE") && !this.check("EOF")) {
      const err = ParserErrors.expectedNewline(this.peek().type);
      throw new ParseError(err.message, this.peek(), err.hint);
    }
    this.match("NEWLINE");
  }

  private skipNewlines(): void {
    while (this.match("NEWLINE")) {}
  }

  // Skip newlines and indentation inside bracketed expressions (lists, maps, call args)
  private skipBracketedWhitespace(): void {
    while (this.match("NEWLINE") || this.match("INDENT") || this.match("DEDENT")) {}
  }
}
