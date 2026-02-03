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
  type ReferenceParams,
  type PrepareRenameParams,
} from "vscode-languageserver/node";
import { TextDocument } from "vscode-languageserver-textdocument";

// Reuse from src - single source of truth for language capabilities
import { Parser } from "../../src/parser";
import { TypeChecker } from "../../src/types/checker";
import { KEYWORDS } from "../../src/lexer/tokens";
import { STDLIB_FUNCTIONS, isBuiltin } from "../../src/shared/stdlib";
import { typeToString, Types } from "../../src/types/types";
import { stdlibSource, STDLIB_PATH_URI } from "../../src/stdlib";
import { visit } from "../../src/types/ast-visitor";
import { astTypeToType, getIterableElementType } from "../../src/types/type-utils";
import type { Program, FnDecl, TypeDecl, ASTNode, Expr, Block, ExternFnDecl, Statement } from "../../src/parser/ast";
import type { Type, ObjectType, MethodType } from "../../src/types/types";

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);
const cache = new Map<string, { program: Program; types: Map<ASTNode, Type> }>();

// Parse stdlib on startup for jump-to-definition
const stdlibProgram = new Parser(stdlibSource).parse();
const stdlibSymbols = collectStdlibSymbols(stdlibProgram);

interface StdlibSymbol {
  name: string;
  kind: "function" | "extern" | "type";
  loc: { line: number; column: number };
  signature?: string;
  doc?: string;
}

function collectStdlibSymbols(program: Program): Map<string, StdlibSymbol> {
  const syms = new Map<string, StdlibSymbol>();
  for (const stmt of program.body) {
    if (stmt.kind === "FnDecl") {
      const fn = stmt as FnDecl;
      const params = fn.params.map(p => `${p.name}: ${p.type ? formatType(p.type) : "any"}`).join(", ");
      const ret = fn.returnType ? formatType(fn.returnType) : "void";
      const typeParams = fn.typeParams?.length ? `[${fn.typeParams.map(t => t.name).join(", ")}]` : "";
      const signature = `fn ${fn.name}${typeParams}(${params}): ${ret}`;
      const doc = getDocstring(fn.body);
      syms.set(fn.name, { name: fn.name, kind: "function", loc: stmt.loc, signature, doc });
    } else if (stmt.kind === "ExternFnDecl") {
      const fn = stmt as ExternFnDecl;
      const params = fn.params.map(p => `${p.name}: ${p.type ? formatType(p.type) : "any"}`).join(", ");
      const ret = fn.returnType ? formatType(fn.returnType) : "void";
      const typeParams = fn.typeParams?.length ? `[${fn.typeParams.map(t => t.name).join(", ")}]` : "";
      const signature = `extern fn ${fn.name}${typeParams}(${params}): ${ret}`;
      syms.set(fn.name, { name: fn.name, kind: "extern", loc: stmt.loc, signature });
    } else if (stmt.kind === "TypeDecl") {
      const t = stmt as TypeDecl;
      const { sig, fields } = getTypeSignature(t);
      const doc = fields.length ? `**Fields:**\n${fields.map(f => `- \`${f}\``).join("\n")}` : undefined;
      syms.set(t.name, { name: t.name, kind: "type", loc: stmt.loc, signature: `type ${sig}`, doc });
    }
  }
  return syms;
}

// Derive keyword list from lexer tokens
const KEYWORD_LIST = Object.keys(KEYWORDS);

// Built-in primitive type names (non-generic)
const BUILTIN_PRIMITIVE_TYPES = ["number", "string", "bool", "null", "bytes", "any", "never", "void"];

// Collect type completions from stdlib type declarations
interface TypeMemberInfo {
  name: string;
  kind: "field" | "method";
  signature: string;
  doc?: string;
}

function collectStdlibTypeMembers(program: Program): Map<string, TypeMemberInfo[]> {
  const result = new Map<string, TypeMemberInfo[]>();
  for (const stmt of program.body) {
    if (stmt.kind !== "TypeDecl") continue;
    const t = stmt as TypeDecl;
    const members: TypeMemberInfo[] = [];
    for (const m of t.body?.members || []) {
      if (m.kind === "FieldDecl") {
        members.push({
          name: m.name,
          kind: "field",
          signature: m.type ? formatType(m.type) : "any",
        });
      } else if (m.kind === "MethodDecl") {
        const params = (m.params || []).map(p => `${p.name}${p.optional ? "?" : ""}: ${p.type ? formatType(p.type) : "any"}`).join(", ");
        const ret = m.returnType ? formatType(m.returnType) : "void";
        const doc = m.body ? getDocstring(m.body) : undefined;
        members.push({
          name: m.name,
          kind: "method",
          signature: `fn(${params}): ${ret}`,
          doc,
        });
      }
    }
    if (members.length > 0) {
      result.set(t.name, members);
    }
  }
  return result;
}

// Build completions from stdlib type members
const stdlibTypeMembers = collectStdlibTypeMembers(stdlibProgram);

function getTypeCompletions(typeName: string): CompletionItem[] {
  const members = stdlibTypeMembers.get(typeName);
  if (!members) return [];
  return members.map(m => ({
    label: m.name,
    kind: m.kind === "field" ? CompletionItemKind.Property : CompletionItemKind.Method,
    detail: m.signature,
    documentation: m.doc,
  }));
}

connection.onInitialize((_params: InitializeParams): InitializeResult => ({
  capabilities: {
    textDocumentSync: TextDocumentSyncKind.Incremental,
    completionProvider: { triggerCharacters: [".", ":"], resolveProvider: true },
    hoverProvider: true,
    documentSymbolProvider: true,
    definitionProvider: true,
    referencesProvider: true,
    renameProvider: { prepareProvider: true },
  },
}));

// Scope-aware AST walker for references/rename (tracks scope context)
type ScopedVisitor = {
  onIdent?: (name: string, loc: { line: number; column: number }, scope: string) => void;
  onMember?: (prop: string, loc: { line: number; column: number }) => void;
};

function walkWithScope(program: Program, v: ScopedVisitor): void {
  function expr(e: any, scope: string): void {
    if (!e) return;
    if (e.kind === "Identifier") {
      v.onIdent?.(e.name, e.loc, scope);
    } else if (e.kind === "MemberExpr") {
      v.onMember?.(e.property, e.loc);
      expr(e.object, scope);
    } else if (e.kind === "CallExpr") {
      expr(e.callee, scope);
      for (const a of e.args || []) expr(a.value ?? a, scope);
    } else if (e.kind === "BinaryExpr" || e.kind === "PipeExpr") {
      expr(e.left, scope); expr(e.right, scope);
    } else if (e.kind === "UnaryExpr") {
      expr(e.operand, scope);
    } else if (e.kind === "IndexExpr") {
      expr(e.object, scope); expr(e.index, scope);
    } else if (e.kind === "LambdaExpr") {
      e.body?.kind === "Block" ? block(e.body, scope) : expr(e.body, scope);
    } else if (e.kind === "IfExpr") {
      expr(e.condition, scope); expr(e.then, scope); expr(e.else, scope);
    } else if (e.kind === "ListExpr") {
      for (const el of e.elements || []) el.kind === "SpreadElement" ? expr(el.expr, scope) : expr(el, scope);
    } else if (e.kind === "MapExpr") {
      for (const en of e.entries || []) expr(en.value, scope);
    } else if (e.kind === "RangeExpr") {
      expr(e.start, scope); expr(e.end, scope);
    } else if (e.kind === "MatchExpr") {
      expr(e.value, scope);
      for (const arm of e.arms || []) {
        if (arm.guard) expr(arm.guard, scope);
        arm.body?.kind === "Block" ? block(arm.body, scope) : expr(arm.body, scope);
      }
    } else if (e.kind === "TemplateLiteral") {
      for (const p of e.parts || []) if (p.kind === "TemplateExpr") expr(p.expr, scope);
    } else if (e.kind === "SpawnExpr" || e.kind === "TypeAssertion" || e.kind === "NullAssertion") {
      expr(e.expr, scope);
    }
  }

  function block(b: any, scope: string): void {
    if (!b?.statements) return;
    for (const s of b.statements) stmt(s, scope);
  }

  function stmt(s: any, scope: string): void {
    if (!s) return;
    if (s.kind === "FnDecl") {
      block(s.body, s.name);
    } else if (s.kind === "TypeDecl") {
      for (const m of s.body?.members || []) {
        if (m.kind === "MethodDecl" && m.body) block(m.body, `${s.name}.${m.name}`);
        if (m.kind === "FieldDecl" && m.defaultValue) expr(m.defaultValue, s.name);
      }
    } else if (s.kind === "LetStmt" || s.kind === "VarStmt") {
      expr(s.value, scope);
    } else if (s.kind === "AssignStmt") {
      expr(s.target, scope); expr(s.value, scope);
    } else if (s.kind === "ExprStmt") {
      expr(s.expr, scope);
    } else if (s.kind === "IfStmt") {
      expr(s.condition, scope);
      s.then?.kind === "Block" ? block(s.then, scope) : stmt(s.then, scope);
      for (const elif of s.elseIfs || []) { expr(elif.condition, scope); block(elif.body, scope); }
      if (s.else) block(s.else, scope);
    } else if (s.kind === "ForStmt") {
      expr(s.iterable, scope); block(s.body, scope);
    } else if (s.kind === "MatchStmt") {
      expr(s.value, scope);
      for (const arm of s.arms || []) {
        if (arm.guard) expr(arm.guard, scope);
        arm.body?.kind === "Block" ? block(arm.body, scope) : stmt(arm.body, scope);
      }
    } else if (s.kind === "ReturnStmt" || s.kind === "YieldStmt" || s.kind === "ThrowStmt") {
      expr(s.value, scope);
    } else if (s.kind === "TryStmt") {
      block(s.body, scope);
      if (s.catch?.body) block(s.catch.body, scope);
    } else if (s.kind === "TestDecl") {
      block(s.body, "test");
    }
  }

  for (const s of program.body) stmt(s, "");
}

// Symbol info for navigation
interface Symbol {
  name: string;
  kind: "function" | "type" | "variable" | "parameter" | "field" | "method";
  scope: string;
  loc: { line: number; column: number };
  offset?: number;
}

function collectSymbols(program: Program): Symbol[] {
  const syms: Symbol[] = [];
  const add = (name: string, kind: Symbol["kind"], scope: string, loc: any, offset = 0) =>
    syms.push({ name, kind, scope, loc, offset });

  for (const s of program.body) {
    if (s.kind === "FnDecl") {
      const fn = s as FnDecl;
      add(fn.name, "function", "", s.loc, 3);
      for (const p of fn.params || []) add(p.name, "parameter", fn.name, p.loc);
      walkBlock(fn.body, fn.name);
    } else if (s.kind === "TypeDecl") {
      const t = s as TypeDecl;
      add(t.name, "type", "", s.loc, 5);
      for (const m of t.body?.members || []) {
        if (m.kind === "FieldDecl") add(m.name, "field", t.name, m.loc);
        else if (m.kind === "MethodDecl") {
          const scope = `${t.name}.${m.name}`;
          add(m.name, "method", t.name, m.loc, 3);
          for (const p of m.params || []) add(p.name, "parameter", scope, p.loc);
          if (m.body) walkBlock(m.body, scope);
        }
      }
    } else if (s.kind === "LetStmt") {
      const ls = s as any;
      if (ls.pattern?.kind === "IdentifierPattern") add(ls.pattern.name, "variable", "", s.loc, 4);
    } else if (s.kind === "VarStmt") {
      add((s as any).name, "variable", "", s.loc, 4);
    } else if (s.kind === "TestDecl") {
      walkBlock((s as any).body, "test");
    }
  }

  function walkBlock(b: any, scope: string) {
    if (!b?.statements) return;
    for (const s of b.statements) {
      if (s.kind === "LetStmt" && s.pattern?.kind === "IdentifierPattern") {
        add(s.pattern.name, "variable", scope, s.loc, 4);
      } else if (s.kind === "VarStmt") {
        add(s.name, "variable", scope, s.loc, 4);
      } else if (s.kind === "ForStmt" && s.pattern?.kind === "IdentifierPattern") {
        add(s.pattern.name, "variable", scope, s.pattern.loc);
      }
    }
  }

  return syms;
}

function findScope(program: Program, line: number): { scope: string; typeName?: string } {
  for (const s of program.body) {
    if (s.loc.line > line) break;
    if (s.kind === "TypeDecl") {
      const t = s as any;
      for (const m of t.body?.members || []) {
        if (m.kind === "MethodDecl" && m.body && m.loc.line <= line) {
          return { scope: `${t.name}.${m.name}`, typeName: t.name };
        }
      }
      if (t.body?.members?.length) return { scope: t.name, typeName: t.name };
    } else if (s.kind === "FnDecl" && s.loc.line <= line) {
      return { scope: (s as FnDecl).name };
    }
  }
  return { scope: "" };
}

// Type resolution
function resolveObject(program: Program, type: Type): ObjectType | null {
  if (type.kind === "object") return type;
  if (type.kind === "optional") return resolveObject(program, (type as any).inner);
  if (type.kind === "union") {
    for (const t of (type as any).types) {
      const o = resolveObject(program, t);
      if (o) return o;
    }
  }
  if (type.kind === "ref") {
    for (const s of program.body) {
      if (s.kind === "TypeDecl" && (s as TypeDecl).name === type.name) {
        const t = s as TypeDecl;
        const props = (t.body?.members || [])
          .filter(m => m.kind === "FieldDecl")
          .map((m: any) => ({ name: m.name, type: {} as Type, optional: m.optional, readonly: false, computed: false }));
        const methods: MethodType[] = (t.body?.members || [])
          .filter(m => m.kind === "MethodDecl")
          .map((m: any) => ({ name: m.name, type: Types.fn([], Types.any) }));
        return { kind: "object", name: t.name, properties: props, methods };
      }
    }
  }
  return null;
}

// Convert AST type to string using shared utilities
function formatType(t: any): string {
  if (!t) return "any";
  try {
    return typeToString(astTypeToType(t));
  } catch {
    return "any";
  }
}

function getDocstring(body: Block): string | undefined {
  const first = body?.statements?.[0];
  if (first?.kind === "ExprStmt" && first.expr?.kind === "Literal" && typeof first.expr.value === "string") {
    return first.expr.value;
  }
}

function formatExpr(e: Expr): string {
  switch (e.kind) {
    case "Literal": return typeof e.value === "string" ? JSON.stringify(e.value) : String(e.value);
    case "Identifier": return e.name;
    default: return "...";
  }
}

// Get type constructor signature with fields
function getTypeSignature(t: TypeDecl): { sig: string; fields: string[] } {
  const fields: string[] = [];
  for (const m of t.body?.members || []) {
    if (m.kind === "FieldDecl") {
      const opt = m.optional ? "?" : "";
      const def = m.defaultValue ? ` = ${formatExpr(m.defaultValue)}` : "";
      const typeStr = m.type ? formatType(m.type) : "any";
      fields.push(`${m.name}${opt}: ${typeStr}${def}`);
    }
  }
  const sig = fields.length ? `${t.name}(${fields.join(", ")})` : t.name;
  return { sig, fields };
}

// Word extraction
function getWord(doc: TextDocument, pos: Position): { word: string; isProperty: boolean; start: number } {
  const line = doc.getText({ start: { line: pos.line, character: 0 }, end: { line: pos.line + 1, character: 0 } });
  const before = line.slice(0, pos.character);
  const after = line.slice(pos.character);
  const wordStart = before.match(/[a-zA-Z_][a-zA-Z0-9_]*$/)?.[0] || "";
  const wordEnd = after.match(/^[a-zA-Z0-9_]*/)?.[0] || "";
  const word = wordStart + wordEnd;
  const beforeWord = before.slice(0, before.length - wordStart.length);
  return { word, isProperty: beforeWord.trimEnd().endsWith("."), start: pos.character - wordStart.length };
}

// Document validation
documents.onDidChangeContent(e => validateDocument(e.document));

async function validateDocument(doc: TextDocument): Promise<void> {
  const diagnostics: Diagnostic[] = [];

  // Skip validation for stdlib virtual document (already type-checked at load time)
  if (doc.uri === STDLIB_PATH_URI) {
    connection.sendDiagnostics({ uri: doc.uri, diagnostics: [] });
    return;
  }

  try {
    const program = new Parser(doc.getText()).parse();
    const result = new TypeChecker().check(program);
    cache.set(doc.uri, { program, types: result.types });

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
    for (const w of result.warnings) {
      diagnostics.push({
        severity: DiagnosticSeverity.Warning,
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
        message: w,
        source: "manuscript",
      });
    }
  } catch (e: any) {
    const m = e.message?.match(/at line (\d+), column (\d+)/);
    diagnostics.push({
      severity: DiagnosticSeverity.Error,
      range: {
        start: { line: m ? +m[1] - 1 : 0, character: m ? +m[2] - 1 : 0 },
        end: { line: m ? +m[1] - 1 : 0, character: (m ? +m[2] : 0) + 1 },
      },
      message: e.message?.replace(/ at line \d+, column \d+$/, "") || "Parse error",
      source: "manuscript",
    });
  }

  connection.sendDiagnostics({ uri: doc.uri, diagnostics });
}

// Completion
connection.onCompletion((params): CompletionItem[] => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];

  const line = doc.getText({ start: { line: params.position.line, character: 0 }, end: params.position });
  const cached = cache.get(params.textDocument.uri);

  // After colon: type completions
  if (line.match(/:\s*$/)) {
    // Primitive types
    const items: CompletionItem[] = BUILTIN_PRIMITIVE_TYPES.map(t => ({ label: t, kind: CompletionItemKind.TypeParameter }));
    // Stdlib types (Channel, Error, Result, etc.)
    for (const [name, sym] of stdlibSymbols) {
      if (sym.kind === "type") items.push({ label: name, kind: CompletionItemKind.Class });
    }
    // User-defined types
    if (cached) {
      for (const s of cached.program.body) {
        if (s.kind === "TypeDecl") items.push({ label: (s as TypeDecl).name, kind: CompletionItemKind.Class });
      }
    }
    return items;
  }

  // After dot: member completions
  if (line.match(/\.\s*$/)) {
    if (cached) {
      let bestExpr: Expr | null = null;
      const oneBasedLine = params.position.line + 1;
      const oneBasedCol = params.position.character;
      visit(cached.program, {
        expr(e) {
          if (!e?.loc || e.loc.line !== oneBasedLine) return;
          if (e.loc.column <= oneBasedCol) bestExpr = e;
        },
      });
      const type = bestExpr ? cached.types.get(bestExpr) : undefined;
      if (type) {
        // Try stdlib type members first (string, list, map, set)
        const stdlibCompletions = getTypeCompletions(type.kind);
        if (stdlibCompletions.length > 0) return stdlibCompletions;
        // Then try user-defined object types
        const obj = resolveObject(cached.program, type);
        if (obj) {
          return [
            ...obj.properties.map(p => ({ label: p.name, kind: CompletionItemKind.Property, detail: typeToString(p.type) })),
            ...obj.methods.map(m => ({ label: m.name, kind: CompletionItemKind.Method, detail: typeToString(m.type) })),
          ];
        }
      }
    }
    // Fallback: common methods from stdlib list type
    return getTypeCompletions("list");
  }

  // Default: keywords, functions, variables
  const items: CompletionItem[] = [
    ...KEYWORD_LIST.map(k => ({ label: k, kind: CompletionItemKind.Keyword })),
    ...[...STDLIB_FUNCTIONS].map(f => ({ label: f, kind: CompletionItemKind.Function, data: { fn: f } })),
  ];

  if (cached) {
    for (const s of cached.program.body) {
      if (s.kind === "FnDecl") {
        items.push({ label: (s as FnDecl).name, kind: CompletionItemKind.Function, data: { uri: params.textDocument.uri, fn: (s as FnDecl).name } });
      } else if (s.kind === "TypeDecl") {
        const t = s as TypeDecl;
        const { sig } = getTypeSignature(t);
        items.push({ label: t.name, kind: CompletionItemKind.Class, detail: sig, data: { uri: params.textDocument.uri, type: t.name } });
      } else if (s.kind === "LetStmt" || s.kind === "VarStmt") {
        const name = (s as any).name || (s as any).pattern?.name;
        if (name) items.push({ label: name, kind: CompletionItemKind.Variable });
      }
    }
  }

  return items;
});

connection.onCompletionResolve((item): CompletionItem => {
  const data = item.data as { fn?: string; type?: string; uri?: string } | undefined;
  if (!data) return item;

  // Built-in function docs from stdlib
  if (data.fn) {
    const sym = stdlibSymbols.get(data.fn);
    if (sym?.doc) {
      item.documentation = { kind: MarkupKind.Markdown, value: sym.doc };
      return item;
    }
  }

  if (data.uri) {
    const cached = cache.get(data.uri);
    for (const s of cached?.program.body || []) {
      // Function completion
      if (data.fn && s.kind === "FnDecl" && (s as FnDecl).name === data.fn) {
        const fn = s as FnDecl;
        const params = fn.params.map(p => `${p.name}: ${p.type ? formatType(p.type) : "any"}`).join(", ");
        item.detail = `fn ${fn.name}(${params}): ${fn.returnType ? formatType(fn.returnType) : "any"}`;
        const doc = getDocstring(fn.body);
        if (doc) item.documentation = { kind: MarkupKind.Markdown, value: doc };
        break;
      }
      // Type constructor completion
      if (data.type && s.kind === "TypeDecl" && (s as TypeDecl).name === data.type) {
        const t = s as TypeDecl;
        const { fields } = getTypeSignature(t);
        if (fields.length) {
          item.documentation = { kind: MarkupKind.Markdown, value: `**Fields:**\n${fields.map(f => `- \`${f}\``).join("\n")}` };
        }
        break;
      }
    }
  }

  return item;
});

// Find the AST node at a given position (1-based line/column to match AST locations)
function findNodeAtPosition(program: Program, line: number, col: number): { node: ASTNode; kind: string } | null {
  let best: { node: ASTNode; kind: string } | null = null;
  
  function check(node: any, kind: string) {
    if (!node?.loc) return;
    if (node.loc.line === line && node.loc.column <= col) {
      if (!best || node.loc.column >= (best.node as any).loc.column) {
        best = { node, kind };
      }
    }
  }

  function checkIdentifier(e: Expr) {
    if (e.kind === "Identifier") {
      const endCol = e.loc.column + e.name.length;
      if (e.loc.line === line && e.loc.column <= col && col <= endCol) {
        check(e, "Identifier");
      }
    }
  }

  function checkBindingSites(s: Statement) {
    if (s.kind === "FnDecl") {
      const nameStart = s.loc.column + 3; // "fn "
      if (s.loc.line === line && nameStart <= col && col <= nameStart + s.name.length) {
        check(s, "FnDecl");
      }
      for (const p of s.params || []) {
        const endCol = p.loc.column + p.name.length;
        if (p.loc.line === line && p.loc.column <= col && col <= endCol) {
          check(p, "Parameter");
        }
      }
    } else if (s.kind === "TypeDecl") {
      const nameStart = s.loc.column + 5; // "type "
      if (s.loc.line === line && nameStart <= col && col <= nameStart + s.name.length) {
        check(s, "TypeDecl");
      }
      for (const m of s.body?.members || []) {
        if (m.kind === "MethodDecl") {
          for (const p of m.params || []) {
            const endCol = p.loc.column + p.name.length;
            if (p.loc.line === line && p.loc.column <= col && col <= endCol) {
              check(p, "Parameter");
            }
          }
        }
      }
    } else if (s.kind === "LetStmt" && s.pattern?.kind === "IdentifierPattern") {
      const nameStart = s.loc.column + 4; // "let "
      if (s.loc.line === line && nameStart <= col && col <= nameStart + s.pattern.name.length) {
        check({ ...s, name: s.pattern.name }, "LetBinding");
      }
    } else if (s.kind === "VarStmt") {
      const nameStart = s.loc.column + 4; // "var "
      if (s.loc.line === line && nameStart <= col && col <= nameStart + s.name.length) {
        check(s, "VarBinding");
      }
    } else if (s.kind === "ForStmt" && s.pattern?.kind === "IdentifierPattern") {
      const endCol = s.pattern.loc.column + s.pattern.name.length;
      if (s.pattern.loc.line === line && s.pattern.loc.column <= col && col <= endCol) {
        check({ ...s.pattern, iterable: s.iterable }, "ForBinding");
      }
    }
  }

  visit(program, {
    expr: checkIdentifier,
    stmt: checkBindingSites,
  });
  
  return best;
}

// Find information about an identifier in the program context
interface IdentifierInfo {
  type: Type | null;
  doc?: string;
  declarationKind?: "let" | "var" | "parameter" | "for" | "function" | "type";
}

function findIdentifierInfo(program: Program, types: Map<ASTNode, Type>, name: string, line: number): IdentifierInfo {
  let result: IdentifierInfo = { type: null };
  
  // Search for declaration in scope
  function searchScope(statements: any[], scopeLine: number): boolean {
    for (const s of statements) {
      if (s.loc.line > scopeLine) continue;
      
      if (s.kind === "LetStmt" && s.pattern?.kind === "IdentifierPattern" && s.pattern.name === name) {
        result.type = types.get(s.value) || null;
        result.declarationKind = "let";
        return true;
      }
      if (s.kind === "VarStmt" && s.name === name) {
        result.type = types.get(s.value) || null;
        result.declarationKind = "var";
        return true;
      }
      if (s.kind === "FnDecl" && s.name === name) {
        result.type = types.get(s) || null;
        result.doc = getDocstring(s.body);
        result.declarationKind = "function";
        return true;
      }
      if (s.kind === "FnDecl" && s.loc.line <= line) {
        // Check if we're inside this function
        for (const p of s.params || []) {
          if (p.name === name) {
            result.type = p.type ? convertAstTypeToCheckerType(p.type) : null;
            result.declarationKind = "parameter";
            return true;
          }
        }
        // Search function body
        if (s.body?.statements && searchScope(s.body.statements, line)) return true;
      }
      if (s.kind === "ForStmt" && s.pattern?.kind === "IdentifierPattern" && s.pattern.name === name && s.loc.line <= line) {
        const iterType = types.get(s.iterable);
        result.type = iterType ? getIterableElementType(iterType) : Types.any;
        result.declarationKind = "for";
        return true;
      }
      if (s.kind === "IfStmt") {
        if (s.then?.statements && searchScope(s.then.statements, line)) return true;
        for (const elif of s.elseIfs || []) {
          if (elif.body?.statements && searchScope(elif.body.statements, line)) return true;
        }
        if (s.else?.statements && searchScope(s.else.statements, line)) return true;
      }
    }
    return false;
  }
  
  searchScope(program.body, line);
  return result;
}

// Convert AST type annotation to checker Type - use shared utility
function convertAstTypeToCheckerType(astType: any): Type | null {
  if (!astType) return null;
  try {
    return astTypeToType(astType);
  } catch {
    return Types.any;
  }
}

// Hover
connection.onHover((params): Hover | null => {
  const doc = documents.get(params.textDocument.uri);
  const cached = cache.get(params.textDocument.uri);
  if (!doc || !cached) return null;

  const { word, isProperty } = getWord(doc, params.position);
  if (!word) return null;

  const oneBasedLine = params.position.line + 1;
  const oneBasedCol = params.position.character + 1;

  // Property access hover
  if (isProperty) {
    // Try to find the object being accessed and its type
    let objectExpr: Expr | null = null;
    visit(cached.program, {
      expr(e) {
        if (e.kind === "MemberExpr" && e.property === word && e.loc.line === oneBasedLine) {
          objectExpr = (e as any).object;
        }
      },
    });
    
    if (objectExpr) {
      const objType = cached.types.get(objectExpr);
      if (objType) {
        const obj = resolveObject(cached.program, objType);
        if (obj) {
          // Check fields
          const field = obj.properties.find(p => p.name === word);
          if (field) {
            return hover(`(property) ${word}: ${typeToString(field.type)}`);
          }
          // Check methods
          const method = obj.methods.find(m => m.name === word);
          if (method) {
            return hover(`(method) ${word}: ${typeToString(method.type)}`);
          }
        }
      }
    }

    // Fallback: search type declarations for matching member
    for (const s of cached.program.body) {
      if (s.kind !== "TypeDecl") continue;
      const t = s as TypeDecl;
      for (const m of t.body?.members || []) {
        if (m.name !== word) continue;
        if (m.kind === "FieldDecl") {
          return hover(`(property) ${word}: ${m.type ? formatType(m.type) : "any"}`);
        }
        if (m.kind === "MethodDecl") {
          const params = (m.params || []).map(p => `${p.name}: ${p.type ? formatType(p.type) : "any"}`).join(", ");
          const ret = m.returnType ? formatType(m.returnType) : "any";
          return hover(`(method) fn ${word}(${params}): ${ret}`, m.body ? getDocstring(m.body) : undefined);
        }
      }
    }
    // Try to find property/method in stdlib types (string, list, map, set)
    for (const [typeName, members] of stdlibTypeMembers) {
      const member = members.find(m => m.name === word);
      if (member) {
        const prefix = member.kind === "field" ? "(property)" : "(method)";
        return hover(`${prefix} ${word}: ${member.signature}`, member.doc);
      }
    }
    return null;
  }

  // Try to find the exact node at position and get its type
  const nodeInfo = findNodeAtPosition(cached.program, oneBasedLine, oneBasedCol);
  
  if (nodeInfo) {
    const { node, kind } = nodeInfo;
    
    if (kind === "Identifier") {
      // Look up the identifier's type from the type checker
      const identType = cached.types.get(node);
      if (identType) {
        const identInfo = findIdentifierInfo(cached.program, cached.types, (node as any).name, oneBasedLine);
        const prefix = identInfo.declarationKind === "parameter" ? "(parameter)" :
                       identInfo.declarationKind === "for" ? "(for variable)" :
                       identInfo.declarationKind === "function" ? "(function)" :
                       identInfo.declarationKind === "let" ? "(let)" :
                       identInfo.declarationKind === "var" ? "(var)" : "(variable)";
        return hover(`${prefix} ${(node as any).name}: ${typeToString(identType)}`, identInfo.doc);
      }
    }
    
    if (kind === "Parameter") {
      const param = node as any;
      const paramType = param.type ? formatType(param.type) : "any";
      return hover(`(parameter) ${param.name}: ${paramType}`);
    }
    
    if (kind === "LetBinding") {
      const binding = node as any;
      const valueType = cached.types.get(binding.value);
      return hover(`(let) ${binding.name}: ${valueType ? typeToString(valueType) : "any"}`);
    }
    
    if (kind === "VarBinding") {
      const binding = node as any;
      const valueType = cached.types.get(binding.value);
      return hover(`(var) ${binding.name}: ${valueType ? typeToString(valueType) : "any"}`);
    }
    
    if (kind === "ForBinding") {
      const binding = node as any;
      const iterType = cached.types.get(binding.iterable);
      const elemType = iterType ? typeToString(getIterableElementType(iterType)) : "any";
      return hover(`(for variable) ${binding.name}: ${elemType}`);
    }
  }

  // Function/type hover by name lookup
  for (const s of cached.program.body) {
    if (s.kind === "FnDecl" && (s as FnDecl).name === word) {
      const fn = s as FnDecl;
      const params = fn.params.map(p => `${p.name}: ${p.type ? formatType(p.type) : "any"}`).join(", ");
      return hover(`fn ${fn.name}(${params}): ${fn.returnType ? formatType(fn.returnType) : "any"}`, getDocstring(fn.body));
    }
    if (s.kind === "TypeDecl" && (s as TypeDecl).name === word) {
      const t = s as TypeDecl;
      const { sig, fields } = getTypeSignature(t);
      const fieldDocs = fields.length ? `**Fields:**\n${fields.map(f => `- \`${f}\``).join("\n")}` : undefined;
      return hover(`type ${sig}`, fieldDocs);
    }
  }

  // Try looking up identifier type by name if node lookup didn't work
  const identInfo = findIdentifierInfo(cached.program, cached.types, word, oneBasedLine);
  if (identInfo.type) {
    const prefix = identInfo.declarationKind === "parameter" ? "(parameter)" :
                   identInfo.declarationKind === "for" ? "(for variable)" :
                   identInfo.declarationKind === "function" ? "(function)" :
                   identInfo.declarationKind === "let" ? "(let)" :
                   identInfo.declarationKind === "var" ? "(var)" : "(variable)";
    return hover(`${prefix} ${word}: ${typeToString(identInfo.type)}`, identInfo.doc);
  }

  // Stdlib functions and types with full signatures
  const stdlibSym = stdlibSymbols.get(word);
  if (stdlibSym) {
    if (stdlibSym.signature) {
      return hover(stdlibSym.signature, stdlibSym.doc);
    }
    return { contents: { kind: MarkupKind.Markdown, value: `**${word}** - Built-in function.` } };
  }
  
  // Keywords and builtin primitive types
  if (KEYWORD_LIST.includes(word)) return { contents: { kind: MarkupKind.Markdown, value: `**${word}** - Manuscript keyword` } };
  if (BUILTIN_PRIMITIVE_TYPES.includes(word)) return { contents: { kind: MarkupKind.Markdown, value: `**${word}** - Built-in type` } };

  return null;
});

function hover(sig: string, doc?: string): Hover {
  const code = sig ? `\`\`\`manuscript\n${sig}\n\`\`\`` : "";
  return { contents: { kind: MarkupKind.Markdown, value: code + (doc ? `\n\n${doc}` : "") } };
}

// Document symbols
connection.onDocumentSymbol((params): DocumentSymbol[] => {
  const cached = cache.get(params.textDocument.uri);
  if (!cached) return [];

  return cached.program.body
    .filter(s => s.kind === "FnDecl" || s.kind === "TypeDecl" || s.kind === "TestDecl")
    .map(s => {
      const name = s.kind === "TestDecl" ? `test "${(s as any).name}"` : (s as any).name;
      const kind = s.kind === "FnDecl" ? SymbolKind.Function : s.kind === "TypeDecl" ? SymbolKind.Class : SymbolKind.Method;
      const range = { start: { line: s.loc.line - 1, character: s.loc.column - 1 }, end: { line: s.loc.line - 1, character: s.loc.column + name.length } };
      return { name, kind, range, selectionRange: range };
    });
});

// Definition
connection.onDefinition((params): Definition | null => {
  const doc = documents.get(params.textDocument.uri);
  const cached = cache.get(params.textDocument.uri);
  if (!doc || !cached) return null;

  const { word, isProperty } = getWord(doc, params.position);
  if (!word) return null;

  // Property: find in type members
  if (isProperty) {
    for (const s of cached.program.body) {
      if (s.kind !== "TypeDecl") continue;
      for (const m of (s as TypeDecl).body?.members || []) {
        if (m.name === word) {
          const col = m.loc.column - 1 + (m.kind === "MethodDecl" ? 3 : 0);
          return Location.create(params.textDocument.uri, {
            start: { line: m.loc.line - 1, character: col },
            end: { line: m.loc.line - 1, character: col + word.length },
          });
        }
      }
    }
    return null;
  }

  // Jump to stdlib for built-ins
  if (isBuiltin(word)) {
    const sym = stdlibSymbols.get(word);
    if (sym) {
      // Calculate column offset for different declaration kinds
      let offset = 0;
      if (sym.kind === "function") offset = 3; // "fn "
      else if (sym.kind === "extern") offset = 10; // "extern fn "
      else if (sym.kind === "type") offset = 5; // "type "
      
      const col = sym.loc.column - 1 + offset;
      return Location.create(STDLIB_PATH_URI, {
        start: { line: sym.loc.line - 1, character: col },
        end: { line: sym.loc.line - 1, character: col + word.length },
      });
    }
    return null;
  }

  // Find symbol with scope awareness
  const syms = collectSymbols(cached.program);
  const { scope, typeName } = findScope(cached.program, params.position.line + 1);

  let sym = scope.includes(".")
    ? syms.find(s => s.name === word && s.scope === scope) || (typeName ? syms.find(s => s.name === word && s.scope === typeName) : undefined)
    : scope
      ? syms.find(s => s.name === word && s.scope === scope)
      : undefined;

  if (!sym) sym = syms.find(s => s.name === word && s.scope === "");

  if (sym) {
    const col = sym.loc.column - 1 + (sym.offset || 0);
    return Location.create(params.textDocument.uri, {
      start: { line: sym.loc.line - 1, character: col },
      end: { line: sym.loc.line - 1, character: col + word.length },
    });
  }
  return null;
});

// References
connection.onReferences((params): Location[] => {
  const doc = documents.get(params.textDocument.uri);
  const cached = cache.get(params.textDocument.uri);
  if (!doc || !cached) return [];

  const { word, isProperty } = getWord(doc, params.position);
  if (!word) return [];

  const refs: Range[] = [];
  const uri = params.textDocument.uri;

  if (isProperty) {
    for (const s of cached.program.body) {
      if (s.kind === "TypeDecl") {
        for (const m of (s as TypeDecl).body?.members || []) {
          if (m.name === word) {
            const col = m.loc.column - 1 + (m.kind === "MethodDecl" ? 3 : 0);
            refs.push({ start: { line: m.loc.line - 1, character: col }, end: { line: m.loc.line - 1, character: col + word.length } });
          }
        }
      }
    }
    walkWithScope(cached.program, {
      onMember(prop, loc) {
        if (prop === word) refs.push({ start: { line: loc.line - 1, character: loc.column - 1 }, end: { line: loc.line - 1, character: loc.column - 1 + word.length } });
      },
    });
  } else {
    const syms = collectSymbols(cached.program);
    const { scope, typeName } = findScope(cached.program, params.position.line + 1);

    let target = scope.includes(".")
      ? syms.find(s => s.name === word && s.scope === scope) || (typeName ? syms.find(s => s.name === word && s.scope === typeName) : undefined)
      : scope
        ? syms.find(s => s.name === word && s.scope === scope)
        : undefined;
    if (!target) target = syms.find(s => s.name === word && s.scope === "");
    if (!target) return [];

    const col = target.loc.column - 1 + (target.offset || 0);
    refs.push({ start: { line: target.loc.line - 1, character: col }, end: { line: target.loc.line - 1, character: col + word.length } });

    walkWithScope(cached.program, {
      onIdent(name, loc, currentScope) {
        if (name !== word) return;
        if ((target!.kind === "parameter" || target!.kind === "variable") && target!.scope !== "") {
          if (currentScope !== target!.scope && !currentScope.startsWith(target!.scope + ".")) return;
        }
        refs.push({ start: { line: loc.line - 1, character: loc.column - 1 }, end: { line: loc.line - 1, character: loc.column - 1 + word.length } });
      },
    });
  }

  return refs.map(r => Location.create(uri, r));
});

// Rename
connection.onPrepareRename((params): Range | null => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;

  const { word, isProperty, start } = getWord(doc, params.position);
  if (!word || isProperty) return null;
  if (isBuiltin(word) || KEYWORD_LIST.includes(word) || BUILTIN_PRIMITIVE_TYPES.includes(word)) return null;

  return { start: { line: params.position.line, character: start }, end: { line: params.position.line, character: start + word.length } };
});

connection.onRenameRequest((params): WorkspaceEdit | null => {
  const doc = documents.get(params.textDocument.uri);
  const cached = cache.get(params.textDocument.uri);
  if (!doc || !cached) return null;

  const { word, isProperty } = getWord(doc, params.position);
  if (!word || isProperty) return null;
  if (isBuiltin(word) || KEYWORD_LIST.includes(word) || BUILTIN_PRIMITIVE_TYPES.includes(word)) return null;

  const ranges: Range[] = [];
  const syms = collectSymbols(cached.program);
  const { scope, typeName } = findScope(cached.program, params.position.line + 1);

  let target = scope.includes(".")
    ? syms.find(s => s.name === word && s.scope === scope) || (typeName ? syms.find(s => s.name === word && s.scope === typeName) : undefined)
    : scope
      ? syms.find(s => s.name === word && s.scope === scope)
      : undefined;
  if (!target) target = syms.find(s => s.name === word && s.scope === "");
  if (!target) return null;

  const col = target.loc.column - 1 + (target.offset || 0);
  ranges.push({ start: { line: target.loc.line - 1, character: col }, end: { line: target.loc.line - 1, character: col + word.length } });

  walkWithScope(cached.program, {
    onIdent(name, loc, currentScope) {
      if (name !== word) return;
      if ((target!.kind === "parameter" || target!.kind === "variable") && target!.scope !== "") {
        if (currentScope !== target!.scope && !currentScope.startsWith(target!.scope + ".")) return;
      }
      ranges.push({ start: { line: loc.line - 1, character: loc.column - 1 }, end: { line: loc.line - 1, character: loc.column - 1 + word.length } });
    },
  });

  if (ranges.length === 0) return null;

  return { changes: { [params.textDocument.uri]: ranges.map(r => ({ range: r, newText: params.newName })) } };
});

documents.listen(connection);
connection.listen();
