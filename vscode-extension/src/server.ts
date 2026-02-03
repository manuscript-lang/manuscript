import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  type InitializeParams,
  TextDocumentSyncKind,
  type InitializeResult,
  Diagnostic,
  DiagnosticSeverity,
  CompletionItem,
  CompletionItemKind,
  Hover,
  MarkupKind,
  Position,
  type TextDocumentPositionParams,
  DocumentSymbol,
  SymbolKind,
  type Definition,
  Location,
  Range,
  type RenameParams,
  WorkspaceEdit,
  TextEdit,
  type ReferenceParams,
  type PrepareRenameParams,
} from "vscode-languageserver/node";
import { TextDocument } from "vscode-languageserver-textdocument";
// Import only the compiler modules (no runtime capabilities which use Bun)
import { Parser } from "../../src/parser";
import { TypeChecker } from "../../src/types/checker";
import type { Program, FnDecl, TypeDecl, ASTNode } from "../../src/parser/ast";
import type { Type } from "../../src/types/types";

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);

// Cache for parsed documents
const documentCache = new Map<string, { program: Program; types: Map<ASTNode, Type> }>();

connection.onInitialize((_params: InitializeParams): InitializeResult => {
  return {
    capabilities: {
      textDocumentSync: TextDocumentSyncKind.Incremental,
      completionProvider: { triggerCharacters: [".", ":"] },
      hoverProvider: true,
      documentSymbolProvider: true,
      definitionProvider: true,
      referencesProvider: true,
      renameProvider: { prepareProvider: true },
    },
  };
});

// Keywords for completion
const KEYWORDS = [
  "fn", "type", "let", "var", "if", "else", "for", "match", "return",
  "using", "with", "import", "from", "test", "yield", "defer", "try",
  "catch", "throw", "break", "continue", "spawn", "sealed", "extends",
  "and", "or", "not", "is", "as", "then", "in", "true", "false", "null", "where"
];

const BUILTIN_TYPES = [
  "number", "string", "bool", "null", "bytes", "any", "never", "void",
  "list", "map", "set", "Channel", "Promise", "Stream", "Result"
];

const BUILTIN_FUNCTIONS = [
  "print", "len", "range", "clone", "keys", "values", "entries",
  "floor", "ceil", "round", "abs", "min", "max", "sum",
  "int", "float", "str", "type_of", "assert"
];

// Validate document on change
documents.onDidChangeContent((change) => {
  validateDocument(change.document);
});

async function validateDocument(doc: TextDocument): Promise<void> {
  const text = doc.getText();
  const diagnostics: Diagnostic[] = [];

  try {
    const parser = new Parser(text);
    const program = parser.parse();
    
    // Run type checker
    const checker = new TypeChecker();
    const result = checker.check(program);
    
    // Cache the result
    documentCache.set(doc.uri, { program, types: result.types });
    
    // Map type errors to diagnostics
    for (const err of result.errors) {
      diagnostics.push({
        severity: DiagnosticSeverity.Error,
        range: {
          start: { line: err.loc.line - 1, character: err.loc.column - 1 },
          end: { line: err.loc.line - 1, character: err.loc.column + 10 },
        },
        message: err.message.replace(/ at line \d+, column \d+$/, ""),
        source: "manuscript",
      });
    }

    // Add warnings
    for (const warning of result.warnings) {
      diagnostics.push({
        severity: DiagnosticSeverity.Warning,
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
        message: warning,
        source: "manuscript",
      });
    }
  } catch (e: any) {
    // Parse errors
    const match = e.message?.match(/at line (\d+), column (\d+)/);
    const line = match ? parseInt(match[1]) - 1 : 0;
    const col = match ? parseInt(match[2]) - 1 : 0;
    
    diagnostics.push({
      severity: DiagnosticSeverity.Error,
      range: {
        start: { line, character: col },
        end: { line, character: col + 1 },
      },
      message: e.message?.replace(/ at line \d+, column \d+$/, "") || "Parse error",
      source: "manuscript",
    });
  }

  connection.sendDiagnostics({ uri: doc.uri, diagnostics });
}

// Completion
connection.onCompletion((params: TextDocumentPositionParams): CompletionItem[] => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];

  const items: CompletionItem[] = [];
  const line = doc.getText({
    start: { line: params.position.line, character: 0 },
    end: params.position,
  });

  // After colon, suggest types
  if (line.match(/:\s*$/)) {
    for (const t of BUILTIN_TYPES) {
      items.push({ label: t, kind: CompletionItemKind.TypeParameter });
    }
    // Add user-defined types from cache
    const cached = documentCache.get(params.textDocument.uri);
    if (cached) {
      for (const stmt of cached.program.body) {
        if (stmt.kind === "TypeDecl") {
          items.push({ label: (stmt as TypeDecl).name, kind: CompletionItemKind.Class });
        }
      }
    }
    return items;
  }

  // After dot, suggest methods
  if (line.match(/\.\s*$/)) {
    // Common methods for any type
    items.push(
      { label: "length", kind: CompletionItemKind.Property },
      { label: "map", kind: CompletionItemKind.Method },
      { label: "filter", kind: CompletionItemKind.Method },
      { label: "reduce", kind: CompletionItemKind.Method },
      { label: "push", kind: CompletionItemKind.Method },
      { label: "pop", kind: CompletionItemKind.Method },
      { label: "join", kind: CompletionItemKind.Method },
      { label: "split", kind: CompletionItemKind.Method },
      { label: "contains", kind: CompletionItemKind.Method },
      { label: "slice", kind: CompletionItemKind.Method },
    );
    return items;
  }

  // Keywords
  for (const kw of KEYWORDS) {
    items.push({ label: kw, kind: CompletionItemKind.Keyword });
  }

  // Built-in functions
  for (const fn of BUILTIN_FUNCTIONS) {
    items.push({ label: fn, kind: CompletionItemKind.Function });
  }

  // User-defined functions and variables from cache
  const cached = documentCache.get(params.textDocument.uri);
  if (cached) {
    for (const stmt of cached.program.body) {
      if (stmt.kind === "FnDecl") {
        items.push({ label: (stmt as FnDecl).name, kind: CompletionItemKind.Function });
      } else if (stmt.kind === "TypeDecl") {
        items.push({ label: (stmt as TypeDecl).name, kind: CompletionItemKind.Class });
      } else if (stmt.kind === "LetStmt" || stmt.kind === "VarStmt") {
        items.push({ label: (stmt as any).name || (stmt as any).pattern?.name, kind: CompletionItemKind.Variable });
      }
    }
  }

  return items;
});

// Hover
connection.onHover((params: TextDocumentPositionParams): Hover | null => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;

  const cached = documentCache.get(params.textDocument.uri);
  if (!cached) return null;

  // Find word at position
  const line = doc.getText({
    start: { line: params.position.line, character: 0 },
    end: { line: params.position.line + 1, character: 0 },
  });
  
  const col = params.position.character;
  const before = line.slice(0, col);
  const after = line.slice(col);
  
  const wordStart = before.match(/[a-zA-Z_][a-zA-Z0-9_]*$/)?.[0] || "";
  const wordEnd = after.match(/^[a-zA-Z0-9_]*/)?.[0] || "";
  const word = wordStart + wordEnd;
  
  if (!word) return null;

  // Look up in definitions
  for (const stmt of cached.program.body) {
    if (stmt.kind === "FnDecl" && (stmt as FnDecl).name === word) {
      const fn = stmt as FnDecl;
      const params = fn.params.map(p => `${p.name}: ${p.type ? formatTypeExpr(p.type) : "any"}`).join(", ");
      const ret = fn.returnType ? formatTypeExpr(fn.returnType) : "any";
      return {
        contents: {
          kind: MarkupKind.Markdown,
          value: `\`\`\`manuscript\nfn ${fn.name}(${params}): ${ret}\n\`\`\``,
        },
      };
    }
    if (stmt.kind === "TypeDecl" && (stmt as TypeDecl).name === word) {
      const t = stmt as TypeDecl;
      return {
        contents: {
          kind: MarkupKind.Markdown,
          value: `\`\`\`manuscript\ntype ${t.name}\n\`\`\``,
        },
      };
    }
  }

  // Check keywords
  if (KEYWORDS.includes(word)) {
    return {
      contents: {
        kind: MarkupKind.Markdown,
        value: `**${word}** - Manuscript keyword`,
      },
    };
  }

  // Check built-in types
  if (BUILTIN_TYPES.includes(word)) {
    return {
      contents: {
        kind: MarkupKind.Markdown,
        value: `**${word}** - Built-in type`,
      },
    };
  }

  return null;
});

// Document symbols
connection.onDocumentSymbol((params): DocumentSymbol[] => {
  const cached = documentCache.get(params.textDocument.uri);
  if (!cached) return [];

  const symbols: DocumentSymbol[] = [];

  for (const stmt of cached.program.body) {
    if (stmt.kind === "FnDecl") {
      const fn = stmt as FnDecl;
      symbols.push({
        name: fn.name,
        kind: SymbolKind.Function,
        range: {
          start: { line: fn.loc.line - 1, character: fn.loc.column - 1 },
          end: { line: fn.loc.line - 1, character: fn.loc.column + fn.name.length },
        },
        selectionRange: {
          start: { line: fn.loc.line - 1, character: fn.loc.column - 1 },
          end: { line: fn.loc.line - 1, character: fn.loc.column + fn.name.length },
        },
      });
    } else if (stmt.kind === "TypeDecl") {
      const t = stmt as TypeDecl;
      symbols.push({
        name: t.name,
        kind: SymbolKind.Class,
        range: {
          start: { line: t.loc.line - 1, character: t.loc.column - 1 },
          end: { line: t.loc.line - 1, character: t.loc.column + t.name.length },
        },
        selectionRange: {
          start: { line: t.loc.line - 1, character: t.loc.column - 1 },
          end: { line: t.loc.line - 1, character: t.loc.column + t.name.length },
        },
      });
    } else if (stmt.kind === "TestDecl") {
      const test = stmt as any;
      symbols.push({
        name: `test "${test.name}"`,
        kind: SymbolKind.Method,
        range: {
          start: { line: test.loc.line - 1, character: test.loc.column - 1 },
          end: { line: test.loc.line - 1, character: test.loc.column + 4 },
        },
        selectionRange: {
          start: { line: test.loc.line - 1, character: test.loc.column - 1 },
          end: { line: test.loc.line - 1, character: test.loc.column + 4 },
        },
      });
    }
  }

  return symbols;
});

function formatTypeExpr(type: any): string {
  if (!type) return "any";
  switch (type.kind) {
    case "NamedType":
      return type.name;
    case "GenericType":
      return `${type.name}[${type.args.map(formatTypeExpr).join(", ")}]`;
    case "FunctionType":
      return `fn(${type.params.map(formatTypeExpr).join(", ")}): ${formatTypeExpr(type.returnType)}`;
    case "UnionType":
      return type.types.map(formatTypeExpr).join(" or ");
    case "OptionalType":
      return `${formatTypeExpr(type.inner)}?`;
    case "ListType":
      return `list[${formatTypeExpr(type.elementType)}]`;
    default:
      return "any";
  }
}

// Get word at position and determine if it's a property access
function getWordAtPosition(doc: TextDocument, position: Position): { word: string; isProperty: boolean } {
  const line = doc.getText({
    start: { line: position.line, character: 0 },
    end: { line: position.line + 1, character: 0 },
  });
  const col = position.character;
  const before = line.slice(0, col);
  const after = line.slice(col);
  const wordStart = before.match(/[a-zA-Z_][a-zA-Z0-9_]*$/)?.[0] || "";
  const wordEnd = after.match(/^[a-zA-Z0-9_]*/)?.[0] || "";
  const word = wordStart + wordEnd;
  
  // Check if preceded by a dot (property access)
  const beforeWord = before.slice(0, before.length - wordStart.length);
  const isProperty = beforeWord.trimEnd().endsWith(".");
  
  return { word, isProperty };
}

// Scoped symbol with scope path for proper resolution
interface ScopedSymbol {
  name: string;
  kind: "function" | "type" | "variable" | "parameter" | "field" | "method";
  scope: string; // e.g., "", "Hello", "Hello.say_hello"
  loc: { line: number; column: number };
  endLine?: number; // end of scope for this symbol
  nameOffset?: number;
}

// Find which scope contains a given line
function findScopeAtLine(program: Program, line: number): { scope: string; typeName?: string } {
  // Build a list of all scopes with their line ranges
  const scopes: { scope: string; typeName?: string; start: number; end: number }[] = [];
  
  for (let i = 0; i < program.body.length; i++) {
    const stmt = program.body[i]!;
    const nextStmt = program.body[i + 1];
    const nextStart = nextStmt?.loc?.line || Infinity;
    
    if (stmt.kind === "TypeDecl") {
      const typeDecl = stmt as any;
      const typeStart = stmt.loc.line;
      
      if (typeDecl.body?.members) {
        for (let j = 0; j < typeDecl.body.members.length; j++) {
          const member = typeDecl.body.members[j];
          const nextMember = typeDecl.body.members[j + 1];
          
          if (member.kind === "MethodDecl" && member.body) {
            const methodStart = member.loc.line;
            // Method ends at next member or next top-level statement
            const methodEnd = nextMember?.loc?.line ? nextMember.loc.line - 1 : nextStart - 1;
            
            scopes.push({
              scope: `${typeDecl.name}.${member.name}`,
              typeName: typeDecl.name,
              start: methodStart,
              end: methodEnd,
            });
          }
        }
        
        // Type scope (for fields, not inside methods)
        const lastMember = typeDecl.body.members[typeDecl.body.members.length - 1];
        const typeEnd = lastMember?.loc?.line || typeStart;
        scopes.push({
          scope: typeDecl.name,
          typeName: typeDecl.name,
          start: typeStart,
          end: Math.min(typeEnd, nextStart - 1),
        });
      }
    } else if (stmt.kind === "FnDecl") {
      const fnDecl = stmt as any;
      const fnStart = stmt.loc.line;
      const fnEnd = nextStart - 1;
      
      scopes.push({
        scope: fnDecl.name,
        start: fnStart,
        end: fnEnd,
      });
    }
  }
  
  // Find the most specific scope that contains this line
  // Sort by specificity (longer scope = more specific) and start line
  scopes.sort((a, b) => {
    if (a.scope.length !== b.scope.length) return b.scope.length - a.scope.length;
    return b.start - a.start;
  });
  
  for (const s of scopes) {
    if (line >= s.start && line <= s.end) {
      return { scope: s.scope, typeName: s.typeName };
    }
  }
  
  return { scope: "" };
}

// Collect all scoped symbols from AST
function collectScopedSymbols(program: Program): ScopedSymbol[] {
  const symbols: ScopedSymbol[] = [];
  
  function addSymbol(name: string, kind: ScopedSymbol["kind"], scope: string, loc: any, nameOffset?: number) {
    symbols.push({ name, kind, scope, loc, nameOffset });
  }
  
  for (const stmt of program.body) {
    if (stmt.kind === "FnDecl") {
      const fn = stmt as any;
      addSymbol(fn.name, "function", "", stmt.loc, 3);
      // Parameters
      for (const param of fn.params || []) {
        addSymbol(param.name, "parameter", fn.name, param.loc);
      }
      // Walk body for local variables
      walkBlock(fn.body, fn.name);
    } else if (stmt.kind === "TypeDecl") {
      const typeDecl = stmt as any;
      addSymbol(typeDecl.name, "type", "", stmt.loc, 5);
      
      if (typeDecl.body?.members) {
        for (const member of typeDecl.body.members) {
          if (member.kind === "FieldDecl") {
            addSymbol(member.name, "field", typeDecl.name, member.loc);
          } else if (member.kind === "MethodDecl") {
            const methodScope = `${typeDecl.name}.${member.name}`;
            addSymbol(member.name, "method", typeDecl.name, member.loc, 3);
            // Method parameters
            for (const param of member.params || []) {
              addSymbol(param.name, "parameter", methodScope, param.loc);
            }
            // Walk method body
            if (member.body) walkBlock(member.body, methodScope);
          }
        }
      }
    } else if (stmt.kind === "LetStmt") {
      const letStmt = stmt as any;
      if (letStmt.pattern?.kind === "IdentifierPattern") {
        addSymbol(letStmt.pattern.name, "variable", "", stmt.loc, 4);
      }
    } else if (stmt.kind === "VarStmt") {
      addSymbol((stmt as any).name, "variable", "", stmt.loc, 4);
    } else if (stmt.kind === "TestDecl") {
      walkBlock((stmt as any).body, "test");
    }
  }
  
  function walkBlock(block: any, scope: string) {
    if (!block?.statements) return;
    for (const stmt of block.statements) {
      if (stmt.kind === "LetStmt") {
        const letStmt = stmt as any;
        if (letStmt.pattern?.kind === "IdentifierPattern") {
          addSymbol(letStmt.pattern.name, "variable", scope, stmt.loc, 4);
        }
      } else if (stmt.kind === "VarStmt") {
        addSymbol((stmt as any).name, "variable", scope, stmt.loc, 4);
      } else if (stmt.kind === "ForStmt" && (stmt as any).pattern?.kind === "IdentifierPattern") {
        addSymbol((stmt as any).pattern.name, "variable", scope, (stmt as any).pattern.loc);
      }
    }
  }
  
  return symbols;
}

// Find definition with scope awareness
function findDefinitionScoped(uri: string, name: string, line: number): Location | null {
  const cached = documentCache.get(uri);
  if (!cached) return null;

  const symbols = collectScopedSymbols(cached.program);
  const { scope, typeName } = findScopeAtLine(cached.program, line);
  
  // Look up definition based on scope
  let def: ScopedSymbol | undefined;
  
  // If we're inside a type method, look for: 1) local vars, 2) params, 3) fields, 4) global
  if (scope.includes(".")) {
    // Inside a method - check method scope first (locals + params)
    def = symbols.find(s => s.name === name && s.scope === scope);
    // Then check type fields
    if (!def && typeName) {
      def = symbols.find(s => s.name === name && s.scope === typeName && (s.kind === "field" || s.kind === "method"));
    }
  } else if (scope && typeName) {
    // Inside a type but not in method - check type fields
    def = symbols.find(s => s.name === name && s.scope === typeName && (s.kind === "field" || s.kind === "method"));
  } else if (scope) {
    // Inside a function - check function scope first
    def = symbols.find(s => s.name === name && s.scope === scope);
  }
  
  // Fall back to global scope
  if (!def) {
    def = symbols.find(s => s.name === name && s.scope === "" && (s.kind === "function" || s.kind === "type"));
    if (!def) {
      def = symbols.find(s => s.name === name && s.scope === "");
    }
  }
  
  if (def) {
    const col = def.loc.column - 1 + (def.nameOffset || 0);
    return Location.create(uri, {
      start: { line: def.loc.line - 1, character: col },
      end: { line: def.loc.line - 1, character: col + name.length },
    });
  }
  return null;
}

// Collect references with scope awareness
function collectScopedReferences(program: Program, targetName: string, targetScope: string, targetKind: string): Range[] {
  const refs: Range[] = [];
  
  function addRef(loc: any, name: string, currentScope: string) {
    // For fields/methods, only match within the same type
    if ((targetKind === "field" || targetKind === "method") && !currentScope.startsWith(targetScope.split(".")[0]!)) {
      return;
    }
    // For parameters/locals, only match within same scope
    if ((targetKind === "parameter" || targetKind === "variable") && targetScope !== "" && currentScope !== targetScope && !currentScope.startsWith(targetScope + ".")) {
      return;
    }
    if (name === targetName) {
      refs.push({
        start: { line: loc.line - 1, character: loc.column - 1 },
        end: { line: loc.line - 1, character: loc.column - 1 + name.length },
      });
    }
  }
  
  function walkExpr(expr: any, scope: string): void {
    if (!expr) return;
    switch (expr.kind) {
      case "Identifier":
        addRef(expr.loc, expr.name, scope);
        break;
      case "BinaryExpr":
        walkExpr(expr.left, scope);
        walkExpr(expr.right, scope);
        break;
      case "UnaryExpr":
        walkExpr(expr.operand, scope);
        break;
      case "CallExpr":
        walkExpr(expr.callee, scope);
        for (const arg of expr.args || []) {
          if (arg.value) walkExpr(arg.value, scope);
          else walkExpr(arg, scope);
        }
        break;
      case "MemberExpr":
        walkExpr(expr.object, scope);
        break;
      case "IndexExpr":
        walkExpr(expr.object, scope);
        walkExpr(expr.index, scope);
        break;
      case "PipeExpr":
        walkExpr(expr.left, scope);
        walkExpr(expr.right, scope);
        break;
      case "LambdaExpr":
        if (expr.body?.kind === "Block") walkBlock(expr.body, scope);
        else walkExpr(expr.body, scope);
        break;
      case "IfExpr":
        walkExpr(expr.condition, scope);
        walkExpr(expr.then, scope);
        walkExpr(expr.else, scope);
        break;
      case "ListExpr":
        for (const el of expr.elements || []) {
          if (el.kind === "SpreadElement") walkExpr(el.expr, scope);
          else walkExpr(el, scope);
        }
        break;
      case "MapExpr":
        for (const entry of expr.entries || []) {
          if (entry.key?.kind !== "Identifier") walkExpr(entry.key, scope);
          walkExpr(entry.value, scope);
        }
        break;
      case "RangeExpr":
        walkExpr(expr.start, scope);
        walkExpr(expr.end, scope);
        break;
      case "SpawnExpr":
        walkExpr(expr.expr, scope);
        break;
      case "TypeAssertion":
      case "NullAssertion":
        walkExpr(expr.expr, scope);
        break;
      case "TemplateLiteral":
        for (const part of expr.parts || []) {
          if (part.kind === "TemplateExpr") walkExpr(part.expr, scope);
        }
        break;
      case "MatchExpr":
        walkExpr(expr.value, scope);
        for (const arm of expr.arms || []) {
          if (arm.guard) walkExpr(arm.guard, scope);
          if (arm.body?.kind === "Block") walkBlock(arm.body, scope);
          else walkExpr(arm.body, scope);
        }
        break;
    }
  }
  
  function walkBlock(block: any, scope: string): void {
    if (!block?.statements) return;
    for (const stmt of block.statements) {
      walkStmt(stmt, scope);
    }
  }
  
  function walkStmt(stmt: any, scope: string): void {
    switch (stmt.kind) {
      case "FnDecl":
        addRef({ line: stmt.loc.line, column: stmt.loc.column + 3 }, stmt.name, "");
        walkBlock(stmt.body, stmt.name);
        break;
      case "TypeDecl":
        addRef({ line: stmt.loc.line, column: stmt.loc.column + 5 }, stmt.name, "");
        if (stmt.body?.members) {
          for (const member of stmt.body.members) {
            if (member.kind === "FieldDecl") {
              addRef(member.loc, member.name, stmt.name);
              if (member.defaultValue) walkExpr(member.defaultValue, stmt.name);
            } else if (member.kind === "MethodDecl") {
              const methodScope = `${stmt.name}.${member.name}`;
              addRef({ line: member.loc.line, column: member.loc.column + 3 }, member.name, stmt.name);
              if (member.body) walkBlock(member.body, methodScope);
            }
          }
        }
        break;
      case "LetStmt":
        if (stmt.pattern?.kind === "IdentifierPattern") {
          addRef({ line: stmt.pattern.loc.line, column: stmt.pattern.loc.column }, stmt.pattern.name, scope);
        }
        walkExpr(stmt.value, scope);
        break;
      case "VarStmt":
        addRef({ line: stmt.loc.line, column: stmt.loc.column + 4 }, stmt.name, scope);
        walkExpr(stmt.value, scope);
        break;
      case "AssignStmt":
        walkExpr(stmt.target, scope);
        walkExpr(stmt.value, scope);
        break;
      case "ExprStmt":
        walkExpr(stmt.expr, scope);
        break;
      case "IfStmt":
        walkExpr(stmt.condition, scope);
        if (stmt.then?.kind === "Block") walkBlock(stmt.then, scope);
        else walkStmt(stmt.then, scope);
        for (const elif of stmt.elseIfs || []) {
          walkExpr(elif.condition, scope);
          walkBlock(elif.body, scope);
        }
        if (stmt.else) walkBlock(stmt.else, scope);
        break;
      case "ForStmt":
        if (stmt.pattern?.kind === "IdentifierPattern") {
          addRef(stmt.pattern.loc, stmt.pattern.name, scope);
        }
        walkExpr(stmt.iterable, scope);
        walkBlock(stmt.body, scope);
        break;
      case "MatchStmt":
        walkExpr(stmt.value, scope);
        for (const arm of stmt.arms || []) {
          if (arm.guard) walkExpr(arm.guard, scope);
          if (arm.body?.kind === "Block") walkBlock(arm.body, scope);
          else walkExpr(arm.body, scope);
        }
        break;
      case "ReturnStmt":
        walkExpr(stmt.value, scope);
        break;
      case "YieldStmt":
        walkExpr(stmt.value, scope);
        break;
      case "ThrowStmt":
        walkExpr(stmt.value, scope);
        break;
      case "TryStmt":
        walkBlock(stmt.body, scope);
        if (stmt.catch) walkBlock(stmt.catch.body, scope);
        break;
      case "TestDecl":
        walkBlock(stmt.body, "test");
        break;
    }
  }
  
  for (const stmt of program.body) {
    walkStmt(stmt, "");
  }
  
  return refs;
}

// Collect all MemberExpr property usages
function collectMemberExprRefs(program: Program, propertyName: string): Range[] {
  const refs: Range[] = [];
  
  function walkExpr(expr: any): void {
    if (!expr) return;
    switch (expr.kind) {
      case "MemberExpr":
        if (expr.property === propertyName) {
          // Find the actual position of the property (after the dot)
          // The loc might be the start of the whole expression, so we estimate
          refs.push({
            start: { line: expr.loc.line - 1, character: expr.loc.column - 1 },
            end: { line: expr.loc.line - 1, character: expr.loc.column - 1 + propertyName.length },
          });
        }
        walkExpr(expr.object);
        break;
      case "CallExpr":
        walkExpr(expr.callee);
        for (const arg of expr.args || []) {
          if (arg.value) walkExpr(arg.value);
          else walkExpr(arg);
        }
        break;
      case "BinaryExpr":
        walkExpr(expr.left);
        walkExpr(expr.right);
        break;
      case "UnaryExpr":
        walkExpr(expr.operand);
        break;
      case "IndexExpr":
        walkExpr(expr.object);
        walkExpr(expr.index);
        break;
      case "PipeExpr":
        walkExpr(expr.left);
        walkExpr(expr.right);
        break;
      case "IfExpr":
        walkExpr(expr.condition);
        walkExpr(expr.then);
        walkExpr(expr.else);
        break;
      case "ListExpr":
        for (const el of expr.elements || []) {
          if (el.kind === "SpreadElement") walkExpr(el.expr);
          else walkExpr(el);
        }
        break;
      case "MapExpr":
        for (const entry of expr.entries || []) {
          walkExpr(entry.value);
        }
        break;
      case "LambdaExpr":
        if (expr.body?.kind === "Block") walkBlock(expr.body);
        else walkExpr(expr.body);
        break;
      case "TemplateLiteral":
        for (const part of expr.parts || []) {
          if (part.kind === "TemplateExpr") walkExpr(part.expr);
        }
        break;
      case "MatchExpr":
        walkExpr(expr.value);
        for (const arm of expr.arms || []) {
          if (arm.guard) walkExpr(arm.guard);
          if (arm.body?.kind === "Block") walkBlock(arm.body);
          else walkExpr(arm.body);
        }
        break;
      case "SpawnExpr":
        walkExpr(expr.expr);
        break;
      case "TypeAssertion":
      case "NullAssertion":
        walkExpr(expr.expr);
        break;
    }
  }
  
  function walkBlock(block: any): void {
    if (!block?.statements) return;
    for (const stmt of block.statements) walkStmt(stmt);
  }
  
  function walkStmt(stmt: any): void {
    switch (stmt.kind) {
      case "FnDecl":
        walkBlock(stmt.body);
        break;
      case "TypeDecl":
        if (stmt.body?.members) {
          for (const member of stmt.body.members) {
            if (member.kind === "MethodDecl" && member.body) walkBlock(member.body);
            if (member.kind === "FieldDecl" && member.defaultValue) walkExpr(member.defaultValue);
          }
        }
        break;
      case "LetStmt": walkExpr(stmt.value); break;
      case "VarStmt": walkExpr(stmt.value); break;
      case "AssignStmt": walkExpr(stmt.target); walkExpr(stmt.value); break;
      case "ExprStmt": walkExpr(stmt.expr); break;
      case "IfStmt":
        walkExpr(stmt.condition);
        if (stmt.then?.kind === "Block") walkBlock(stmt.then);
        else walkStmt(stmt.then);
        for (const elif of stmt.elseIfs || []) { walkExpr(elif.condition); walkBlock(elif.body); }
        if (stmt.else) walkBlock(stmt.else);
        break;
      case "ForStmt": walkExpr(stmt.iterable); walkBlock(stmt.body); break;
      case "MatchStmt":
        walkExpr(stmt.value);
        for (const arm of stmt.arms || []) {
          if (arm.guard) walkExpr(arm.guard);
          if (arm.body?.kind === "Block") walkBlock(arm.body);
          else walkExpr(arm.body);
        }
        break;
      case "ReturnStmt": walkExpr(stmt.value); break;
      case "YieldStmt": walkExpr(stmt.value); break;
      case "ThrowStmt": walkExpr(stmt.value); break;
      case "TryStmt": walkBlock(stmt.body); if (stmt.catch) walkBlock(stmt.catch.body); break;
      case "TestDecl": walkBlock(stmt.body); break;
    }
  }
  
  for (const stmt of program.body) walkStmt(stmt);
  return refs;
}

// Find all references with scope awareness
function findReferencesScoped(uri: string, name: string, line: number): Location[] {
  const cached = documentCache.get(uri);
  if (!cached) return [];

  const symbols = collectScopedSymbols(cached.program);
  const { scope, typeName } = findScopeAtLine(cached.program, line);
  
  // Find the symbol definition to determine its scope and kind
  let targetSymbol: ScopedSymbol | undefined;
  
  if (scope.includes(".")) {
    targetSymbol = symbols.find(s => s.name === name && s.scope === scope);
    if (!targetSymbol && typeName) {
      targetSymbol = symbols.find(s => s.name === name && s.scope === typeName);
    }
  } else if (typeName) {
    targetSymbol = symbols.find(s => s.name === name && s.scope === typeName);
  } else if (scope) {
    targetSymbol = symbols.find(s => s.name === name && s.scope === scope);
  }
  if (!targetSymbol) {
    targetSymbol = symbols.find(s => s.name === name && s.scope === "");
  }
  
  if (!targetSymbol) return [];
  
  let refs = collectScopedReferences(cached.program, name, targetSymbol.scope, targetSymbol.kind);
  
  // For fields and methods, also include MemberExpr usages (e.g., user.name)
  if (targetSymbol.kind === "field" || targetSymbol.kind === "method") {
    const memberRefs = collectMemberExprRefs(cached.program, name);
    refs = refs.concat(memberRefs);
  }
  
  return refs.map(r => Location.create(uri, r));
}

// Find method/field definition across all types (for property access)
function findMethodOrFieldDefinition(uri: string, name: string): Location | null {
  const cached = documentCache.get(uri);
  if (!cached) return null;

  // Search all types for a method or field with this name
  for (const stmt of cached.program.body) {
    if (stmt.kind === "TypeDecl") {
      const typeDecl = stmt as any;
      if (typeDecl.body?.members) {
        for (const member of typeDecl.body.members) {
          if (member.kind === "FieldDecl" && member.name === name) {
            return Location.create(uri, {
              start: { line: member.loc.line - 1, character: member.loc.column - 1 },
              end: { line: member.loc.line - 1, character: member.loc.column - 1 + name.length },
            });
          }
          if (member.kind === "MethodDecl" && member.name === name) {
            const col = member.loc.column - 1 + 3; // "fn "
            return Location.create(uri, {
              start: { line: member.loc.line - 1, character: col },
              end: { line: member.loc.line - 1, character: col + name.length },
            });
          }
        }
      }
    }
  }
  return null;
}

// Go to Definition
connection.onDefinition((params: TextDocumentPositionParams): Definition | null => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;

  const { word, isProperty } = getWordAtPosition(doc, params.position);
  if (!word) return null;
  
  // For property access (obj.method), search for method/field in all types
  if (isProperty) {
    return findMethodOrFieldDefinition(params.textDocument.uri, word);
  }

  return findDefinitionScoped(params.textDocument.uri, word, params.position.line + 1);
});

// Find method/field references across the document (for property access)
function findMethodOrFieldReferences(uri: string, name: string): Location[] {
  const cached = documentCache.get(uri);
  if (!cached) return [];

  const refs: Location[] = [];
  
  // Find the definition (method or field in a type)
  for (const stmt of cached.program.body) {
    if (stmt.kind === "TypeDecl") {
      const typeDecl = stmt as any;
      if (typeDecl.body?.members) {
        for (const member of typeDecl.body.members) {
          if (member.kind === "FieldDecl" && member.name === name) {
            refs.push(Location.create(uri, {
              start: { line: member.loc.line - 1, character: member.loc.column - 1 },
              end: { line: member.loc.line - 1, character: member.loc.column - 1 + name.length },
            }));
          }
          if (member.kind === "MethodDecl" && member.name === name) {
            const col = member.loc.column - 1 + 3; // "fn "
            refs.push(Location.create(uri, {
              start: { line: member.loc.line - 1, character: col },
              end: { line: member.loc.line - 1, character: col + name.length },
            }));
          }
        }
      }
    }
  }
  
  // Find all MemberExpr usages with this property name
  function walkExpr(expr: any): void {
    if (!expr) return;
    switch (expr.kind) {
      case "MemberExpr":
        if (expr.property === name) {
          // Calculate position of property name (after the dot)
          const objEnd = expr.object?.loc?.column || expr.loc.column;
          refs.push(Location.create(uri, {
            start: { line: expr.loc.line - 1, character: expr.loc.column - 1 },
            end: { line: expr.loc.line - 1, character: expr.loc.column - 1 + name.length },
          }));
        }
        walkExpr(expr.object);
        break;
      case "CallExpr":
        walkExpr(expr.callee);
        for (const arg of expr.args || []) {
          if (arg.value) walkExpr(arg.value);
          else walkExpr(arg);
        }
        break;
      case "BinaryExpr":
        walkExpr(expr.left);
        walkExpr(expr.right);
        break;
      case "UnaryExpr":
        walkExpr(expr.operand);
        break;
      case "IndexExpr":
        walkExpr(expr.object);
        walkExpr(expr.index);
        break;
      case "PipeExpr":
        walkExpr(expr.left);
        walkExpr(expr.right);
        break;
      case "IfExpr":
        walkExpr(expr.condition);
        walkExpr(expr.then);
        walkExpr(expr.else);
        break;
      case "ListExpr":
        for (const el of expr.elements || []) {
          if (el.kind === "SpreadElement") walkExpr(el.expr);
          else walkExpr(el);
        }
        break;
      case "MapExpr":
        for (const entry of expr.entries || []) {
          walkExpr(entry.value);
        }
        break;
      case "LambdaExpr":
        if (expr.body?.kind === "Block") walkBlock(expr.body);
        else walkExpr(expr.body);
        break;
      case "TemplateLiteral":
        for (const part of expr.parts || []) {
          if (part.kind === "TemplateExpr") walkExpr(part.expr);
        }
        break;
      case "MatchExpr":
        walkExpr(expr.value);
        for (const arm of expr.arms || []) {
          if (arm.guard) walkExpr(arm.guard);
          if (arm.body?.kind === "Block") walkBlock(arm.body);
          else walkExpr(arm.body);
        }
        break;
      case "SpawnExpr":
        walkExpr(expr.expr);
        break;
      case "TypeAssertion":
      case "NullAssertion":
        walkExpr(expr.expr);
        break;
    }
  }
  
  function walkBlock(block: any): void {
    if (!block?.statements) return;
    for (const stmt of block.statements) {
      walkStmt(stmt);
    }
  }
  
  function walkStmt(stmt: any): void {
    switch (stmt.kind) {
      case "FnDecl":
        walkBlock(stmt.body);
        break;
      case "TypeDecl":
        if (stmt.body?.members) {
          for (const member of stmt.body.members) {
            if (member.kind === "MethodDecl" && member.body) {
              walkBlock(member.body);
            }
            if (member.kind === "FieldDecl" && member.defaultValue) {
              walkExpr(member.defaultValue);
            }
          }
        }
        break;
      case "LetStmt":
        walkExpr(stmt.value);
        break;
      case "VarStmt":
        walkExpr(stmt.value);
        break;
      case "AssignStmt":
        walkExpr(stmt.target);
        walkExpr(stmt.value);
        break;
      case "ExprStmt":
        walkExpr(stmt.expr);
        break;
      case "IfStmt":
        walkExpr(stmt.condition);
        if (stmt.then?.kind === "Block") walkBlock(stmt.then);
        else walkStmt(stmt.then);
        for (const elif of stmt.elseIfs || []) {
          walkExpr(elif.condition);
          walkBlock(elif.body);
        }
        if (stmt.else) walkBlock(stmt.else);
        break;
      case "ForStmt":
        walkExpr(stmt.iterable);
        walkBlock(stmt.body);
        break;
      case "MatchStmt":
        walkExpr(stmt.value);
        for (const arm of stmt.arms || []) {
          if (arm.guard) walkExpr(arm.guard);
          if (arm.body?.kind === "Block") walkBlock(arm.body);
          else walkExpr(arm.body);
        }
        break;
      case "ReturnStmt":
        walkExpr(stmt.value);
        break;
      case "YieldStmt":
        walkExpr(stmt.value);
        break;
      case "ThrowStmt":
        walkExpr(stmt.value);
        break;
      case "TryStmt":
        walkBlock(stmt.body);
        if (stmt.catch) walkBlock(stmt.catch.body);
        break;
      case "TestDecl":
        walkBlock(stmt.body);
        break;
    }
  }
  
  for (const stmt of cached.program.body) {
    walkStmt(stmt);
  }
  
  return refs;
}

// Find References
connection.onReferences((params: ReferenceParams): Location[] => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];

  const { word, isProperty } = getWordAtPosition(doc, params.position);
  if (!word) return [];
  
  // For property access, find method/field references
  if (isProperty) {
    return findMethodOrFieldReferences(params.textDocument.uri, word);
  }

  return findReferencesScoped(params.textDocument.uri, word, params.position.line + 1);
});

// Prepare Rename (validate rename is possible)
connection.onPrepareRename((params: PrepareRenameParams): Range | null => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;

  const { word, isProperty } = getWordAtPosition(doc, params.position);
  if (!word) return null;
  
  // Don't allow renaming property access or keywords/built-ins
  if (isProperty) return null;
  if (KEYWORDS.includes(word) || BUILTIN_TYPES.includes(word) || BUILTIN_FUNCTIONS.includes(word)) {
    return null;
  }

  const line = doc.getText({
    start: { line: params.position.line, character: 0 },
    end: { line: params.position.line + 1, character: 0 },
  });
  const col = params.position.character;
  const before = line.slice(0, col);
  const startCol = col - (before.match(/[a-zA-Z_][a-zA-Z0-9_]*$/)?.[0]?.length || 0);

  return {
    start: { line: params.position.line, character: startCol },
    end: { line: params.position.line, character: startCol + word.length },
  };
});

// Rename
connection.onRenameRequest((params: RenameParams): WorkspaceEdit | null => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;

  const { word, isProperty } = getWordAtPosition(doc, params.position);
  if (!word) return null;
  
  // Don't allow renaming property access or keywords/built-ins
  if (isProperty) return null;
  if (KEYWORDS.includes(word) || BUILTIN_TYPES.includes(word) || BUILTIN_FUNCTIONS.includes(word)) {
    return null;
  }

  const refs = findReferencesScoped(params.textDocument.uri, word, params.position.line + 1);
  if (refs.length === 0) return null;

  const edits: TextEdit[] = refs.map(ref => ({
    range: ref.range,
    newText: params.newName,
  }));

  return {
    changes: {
      [params.textDocument.uri]: edits,
    },
  };
});

documents.listen(connection);
connection.listen();
