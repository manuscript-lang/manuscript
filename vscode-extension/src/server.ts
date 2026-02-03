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

// Reuse from src
import { Parser } from "../../src/parser";
import { TypeChecker } from "../../src/types/checker";
import { KEYWORDS } from "../../src/lexer/tokens";
import { STDLIB_FUNCTIONS, isBuiltin } from "../../src/shared/stdlib";
import { typeToString, Types } from "../../src/types/types";
import type { Program, FnDecl, TypeDecl, ASTNode, Expr, Block } from "../../src/parser/ast";
import type { Type, ObjectType, MethodType } from "../../src/types/types";

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);
const cache = new Map<string, { program: Program; types: Map<ASTNode, Type> }>();

// Derive keyword list from lexer tokens
const KEYWORD_LIST = Object.keys(KEYWORDS);

// Built-in types (from syntax.md)
const BUILTIN_TYPES = [
  "number", "string", "bool", "null", "bytes", "any", "never", "void",
  "list", "map", "set", "Channel", "Promise", "Stream", "Result", "Error",
];

// Docs for hover/completion
const DOCS: Record<string, string> = {
  print: "Prints a value to output.",
  len: "Returns the length of a list, string, or map.",
  range: "Returns a list of numbers from start to end (exclusive).",
  clone: "Returns a deep copy of a value.",
  keys: "Returns the keys of a map as a list.",
  values: "Returns the values of a map as a list.",
  entries: "Returns a list of {key, value} pairs from a map.",
  contains: "Returns true if the collection contains the item.",
  map: "Transforms each element; returns a new list.",
  filter: "Keeps elements that match the predicate.",
  reduce: "Folds the list to a single value.",
  push: "Adds an item to the end of the list; returns the list.",
  pop: "Removes and returns the last element, or null.",
  join: "Joins list elements with a separator string.",
  split: "Splits a string by delimiter; returns list of strings.",
  length: "Number of characters (string) or elements (list).",
  upper: "Converts string to uppercase.",
  lower: "Converts string to lowercase.",
  trim: "Removes leading/trailing whitespace.",
  slice: "Returns a portion of the collection.",
};

// Type completions by kind
const TYPE_COMPLETIONS: Record<string, CompletionItem[]> = {
  string: [
    { label: "length", kind: CompletionItemKind.Property, detail: "number" },
    { label: "upper", kind: CompletionItemKind.Method, detail: "fn(): string" },
    { label: "lower", kind: CompletionItemKind.Method, detail: "fn(): string" },
    { label: "trim", kind: CompletionItemKind.Method, detail: "fn(): string" },
    { label: "split", kind: CompletionItemKind.Method, detail: "fn(sep: string): list[string]" },
    { label: "contains", kind: CompletionItemKind.Method, detail: "fn(s: string): bool" },
    { label: "starts_with", kind: CompletionItemKind.Method, detail: "fn(prefix: string): bool" },
    { label: "ends_with", kind: CompletionItemKind.Method, detail: "fn(suffix: string): bool" },
    { label: "replace", kind: CompletionItemKind.Method, detail: "fn(from: string, to: string): string" },
    { label: "slice", kind: CompletionItemKind.Method, detail: "fn(start: number, end?: number): string" },
  ],
  list: [
    { label: "length", kind: CompletionItemKind.Property, detail: "number" },
    { label: "push", kind: CompletionItemKind.Method, detail: "fn(item: T): list[T]" },
    { label: "pop", kind: CompletionItemKind.Method, detail: "fn(): T?" },
    { label: "map", kind: CompletionItemKind.Method, detail: "fn(f: fn(T): U): list[U]" },
    { label: "filter", kind: CompletionItemKind.Method, detail: "fn(f: fn(T): bool): list[T]" },
    { label: "reduce", kind: CompletionItemKind.Method, detail: "fn(f: fn(acc, x): acc, init): any" },
    { label: "join", kind: CompletionItemKind.Method, detail: "fn(sep?: string): string" },
    { label: "contains", kind: CompletionItemKind.Method, detail: "fn(item: T): bool" },
    { label: "slice", kind: CompletionItemKind.Method, detail: "fn(start: number, end?: number): list[T]" },
  ],
  map: [
    { label: "get", kind: CompletionItemKind.Method, detail: "fn(key: K): V?" },
    { label: "set", kind: CompletionItemKind.Method, detail: "fn(key: K, value: V): void" },
    { label: "has", kind: CompletionItemKind.Method, detail: "fn(key: K): bool" },
    { label: "keys", kind: CompletionItemKind.Method, detail: "fn(): list[K]" },
    { label: "values", kind: CompletionItemKind.Method, detail: "fn(): list[V]" },
    { label: "entries", kind: CompletionItemKind.Method, detail: "fn(): list[(K, V)]" },
  ],
};

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

// Unified AST walker with callbacks
type Visitor = {
  onExpr?: (e: Expr, scope: string) => void;
  onIdent?: (name: string, loc: { line: number; column: number }, scope: string) => void;
  onMember?: (prop: string, loc: { line: number; column: number }) => void;
};

function walk(program: Program, v: Visitor): void {
  function expr(e: any, scope: string): void {
    if (!e) return;
    v.onExpr?.(e, scope);
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

function formatType(t: any): string {
  if (!t) return "any";
  switch (t.kind) {
    case "NamedType": return t.name ?? "any";
    case "GenericType": return `${t.name}[${(t.args ?? []).map(formatType).join(", ")}]`;
    case "FunctionType": return `fn(${(t.params ?? []).map(formatType).join(", ")}): ${formatType(t.returnType)}`;
    case "UnionType": return (t.types ?? []).map(formatType).join(" or ");
    case "OptionalType": return `${formatType(t.inner)}?`;
    case "ListType": return `list[${formatType(t.elementType)}]`;
    default: return "any";
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
    const items: CompletionItem[] = BUILTIN_TYPES.map(t => ({ label: t, kind: CompletionItemKind.TypeParameter }));
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
      walk(cached.program, {
        onExpr(e) {
          if (!e?.loc || e.loc.line !== oneBasedLine) return;
          if (e.loc.column <= oneBasedCol) bestExpr = e;
        },
      });
      const type = bestExpr ? cached.types.get(bestExpr) : undefined;
      if (type) {
        if (TYPE_COMPLETIONS[type.kind]) return TYPE_COMPLETIONS[type.kind];
        const obj = resolveObject(cached.program, type);
        if (obj) {
          return [
            ...obj.properties.map(p => ({ label: p.name, kind: CompletionItemKind.Property, detail: typeToString(p.type) })),
            ...obj.methods.map(m => ({ label: m.name, kind: CompletionItemKind.Method, detail: typeToString(m.type) })),
          ];
        }
      }
    }
    return [
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
    ];
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

  // Built-in function docs
  if (data.fn && DOCS[data.fn]) {
    item.documentation = { kind: MarkupKind.Markdown, value: DOCS[data.fn] };
    return item;
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

// Hover
connection.onHover((params): Hover | null => {
  const doc = documents.get(params.textDocument.uri);
  const cached = cache.get(params.textDocument.uri);
  if (!doc || !cached) return null;

  const { word, isProperty } = getWord(doc, params.position);
  if (!word) return null;

  // Property access hover
  if (isProperty) {
    for (const s of cached.program.body) {
      if (s.kind !== "TypeDecl") continue;
      const t = s as TypeDecl;
      for (const m of t.body?.members || []) {
        if (m.name !== word) continue;
        if (m.kind === "FieldDecl") {
          return hover(m.type ? `${word}: ${formatType(m.type)}` : word);
        }
        if (m.kind === "MethodDecl") {
          const params = (m.params || []).map(p => `${p.name}: ${p.type ? formatType(p.type) : "any"}`).join(", ");
          const ret = m.returnType ? formatType(m.returnType) : "any";
          return hover(`fn ${word}(${params}): ${ret}`, m.body ? getDocstring(m.body) : undefined);
        }
      }
    }
    if (DOCS[word]) return hover(word === "length" ? "length: number" : "", DOCS[word]);
    return null;
  }

  // Function/type hover
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

  if (STDLIB_FUNCTIONS.has(word)) return { contents: { kind: MarkupKind.Markdown, value: `**${word}**\n\n${DOCS[word] || "Built-in function."}` } };
  if (KEYWORD_LIST.includes(word)) return { contents: { kind: MarkupKind.Markdown, value: `**${word}** - Manuscript keyword` } };
  if (BUILTIN_TYPES.includes(word)) return { contents: { kind: MarkupKind.Markdown, value: `**${word}** - Built-in type` } };

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

  // Skip built-ins
  if (isBuiltin(word)) return null;

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
    walk(cached.program, {
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

    walk(cached.program, {
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
  if (isBuiltin(word) || KEYWORD_LIST.includes(word) || BUILTIN_TYPES.includes(word)) return null;

  return { start: { line: params.position.line, character: start }, end: { line: params.position.line, character: start + word.length } };
});

connection.onRenameRequest((params): WorkspaceEdit | null => {
  const doc = documents.get(params.textDocument.uri);
  const cached = cache.get(params.textDocument.uri);
  if (!doc || !cached) return null;

  const { word, isProperty } = getWord(doc, params.position);
  if (!word || isProperty) return null;
  if (isBuiltin(word) || KEYWORD_LIST.includes(word) || BUILTIN_TYPES.includes(word)) return null;

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

  walk(cached.program, {
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
