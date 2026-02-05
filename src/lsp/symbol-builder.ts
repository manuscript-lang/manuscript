// Symbol Table Builder - Builds symbol table from AST and type information
import * as AST from "../parser/ast";
import type { Type, ObjectType } from "../types/types";
import type { TypeEnvironment } from "../types/environment";
import { SymbolTable, type SymbolId, type SymbolDef } from "./symbols";

interface BuildContext {
  symbols: SymbolTable;
  env: TypeEnvironment;
  program: AST.Program;
  currentScope: string;
}

export function buildSymbolTable(
  program: AST.Program,
  env: TypeEnvironment
): SymbolTable {
  const symbols = new SymbolTable();
  const ctx: BuildContext = {
    symbols,
    env,
    program,
    currentScope: "",
  };

  // First pass: collect all definitions
  for (const stmt of program.body) {
    collectDefinitions(ctx, stmt);
  }

  // Second pass: collect all references
  for (const stmt of program.body) {
    collectReferences(ctx, stmt);
  }

  return symbols;
}

function collectDefinitions(ctx: BuildContext, stmt: AST.Statement): void {
  switch (stmt.kind) {
    case "FnDecl": {
      // Function definition
      ctx.symbols.addDefinition({
        id: { kind: "function", qualifiedName: stmt.name },
        name: stmt.name,
        loc: stmt.loc,
        nameOffset: 3, // "fn "
      });
      // Parameters
      for (const p of stmt.params) {
        ctx.symbols.addDefinition({
          id: { kind: "parameter", qualifiedName: `${stmt.name}.${p.name}` },
          name: p.name,
          loc: p.loc,
          nameOffset: 0,
        });
      }
      // Local variables in function body
      if (stmt.body) {
        const oldScope = ctx.currentScope;
        ctx.currentScope = stmt.name;
        collectBlockDefinitions(ctx, stmt.body);
        ctx.currentScope = oldScope;
      }
      break;
    }
    case "TypeDecl": {
      // Type definition
      ctx.symbols.addDefinition({
        id: { kind: "type", qualifiedName: stmt.name },
        name: stmt.name,
        loc: stmt.loc,
        nameOffset: 5, // "type "
      });
      // Members
      for (const m of stmt.body?.members || []) {
        if (m.kind === "FieldDecl") {
          ctx.symbols.addDefinition({
            id: { kind: "field", qualifiedName: `${stmt.name}.${m.name}` },
            name: m.name,
            loc: m.loc,
            nameOffset: 0,
          });
        } else if (m.kind === "MethodDecl") {
          ctx.symbols.addDefinition({
            id: { kind: "method", qualifiedName: `${stmt.name}.${m.name}` },
            name: m.name,
            loc: m.loc,
            nameOffset: 3, // "fn "
          });
          // Method parameters
          for (const p of m.params) {
            ctx.symbols.addDefinition({
              id: { kind: "parameter", qualifiedName: `${stmt.name}.${m.name}.${p.name}` },
              name: p.name,
              loc: p.loc,
              nameOffset: 0,
            });
          }
          // Local variables in method body
          if (m.body) {
            const oldScope = ctx.currentScope;
            ctx.currentScope = `${stmt.name}.${m.name}`;
            collectBlockDefinitions(ctx, m.body);
            ctx.currentScope = oldScope;
          }
        }
      }
      break;
    }
    case "LetStmt": {
      if (stmt.pattern?.kind === "IdentifierPattern") {
        const scope = ctx.currentScope;
        const qn = scope ? `${scope}.${stmt.pattern.name}` : stmt.pattern.name;
        ctx.symbols.addDefinition({
          id: { kind: "variable", qualifiedName: qn },
          name: stmt.pattern.name,
          loc: stmt.loc,
          nameOffset: 4, // "let "
        });
      }
      break;
    }
    case "VarStmt": {
      const scope = ctx.currentScope;
      const qn = scope ? `${scope}.${stmt.name}` : stmt.name;
      ctx.symbols.addDefinition({
        id: { kind: "variable", qualifiedName: qn },
        name: stmt.name,
        loc: stmt.loc,
        nameOffset: 4, // "var "
      });
      break;
    }
    case "ForStmt": {
      if (stmt.pattern?.kind === "IdentifierPattern") {
        const scope = ctx.currentScope;
        const qn = scope ? `${scope}.${stmt.pattern.name}` : stmt.pattern.name;
        ctx.symbols.addDefinition({
          id: { kind: "variable", qualifiedName: qn },
          name: stmt.pattern.name,
          loc: stmt.pattern.loc,
          nameOffset: 0,
        });
      }
      if (stmt.body) {
        collectBlockDefinitions(ctx, stmt.body);
      }
      break;
    }
  }
}

function collectBlockDefinitions(ctx: BuildContext, block: AST.Block): void {
  for (const stmt of block.statements) {
    collectDefinitions(ctx, stmt);
  }
}

function collectReferences(ctx: BuildContext, stmt: AST.Statement): void {
  switch (stmt.kind) {
    case "FnDecl": {
      const oldScope = ctx.currentScope;
      ctx.currentScope = stmt.name;
      if (stmt.body) collectBlockReferences(ctx, stmt.body);
      ctx.currentScope = oldScope;
      break;
    }
    case "TypeDecl": {
      const oldScope = ctx.currentScope;
      ctx.currentScope = stmt.name;
      for (const m of stmt.body?.members || []) {
        if (m.kind === "FieldDecl" && m.defaultValue) {
          collectExprReferences(ctx, m.defaultValue);
        } else if (m.kind === "MethodDecl" && m.body) {
          ctx.currentScope = `${stmt.name}.${m.name}`;
          collectBlockReferences(ctx, m.body);
          ctx.currentScope = stmt.name;
        }
      }
      ctx.currentScope = oldScope;
      break;
    }
    case "LetStmt":
      collectExprReferences(ctx, stmt.value);
      break;
    case "VarStmt":
      collectExprReferences(ctx, stmt.value);
      break;
    case "AssignStmt":
      collectExprReferences(ctx, stmt.target);
      collectExprReferences(ctx, stmt.value);
      break;
    case "ExprStmt":
      collectExprReferences(ctx, stmt.expr);
      break;
    case "ReturnStmt":
      if (stmt.value) collectExprReferences(ctx, stmt.value);
      break;
    case "IfStmt":
      collectExprReferences(ctx, stmt.condition);
      if (stmt.then.kind === "Block") {
        collectBlockReferences(ctx, stmt.then);
      } else {
        collectReferences(ctx, stmt.then);
      }
      for (const elif of stmt.elseIfs) {
        collectExprReferences(ctx, elif.condition);
        collectBlockReferences(ctx, elif.body);
      }
      if (stmt.else) collectBlockReferences(ctx, stmt.else);
      break;
    case "ForStmt":
      if (stmt.iterable) collectExprReferences(ctx, stmt.iterable);
      collectBlockReferences(ctx, stmt.body);
      break;
    case "MatchStmt":
      collectExprReferences(ctx, stmt.value);
      for (const arm of stmt.arms) {
        if (arm.guard) collectExprReferences(ctx, arm.guard);
        if (arm.body.kind === "Block") {
          collectBlockReferences(ctx, arm.body);
        } else {
          collectExprReferences(ctx, arm.body);
        }
      }
      break;
    case "TryStmt":
      collectBlockReferences(ctx, stmt.body);
      if (stmt.catch) collectBlockReferences(ctx, stmt.catch.body);
      break;
    case "WithStmt":
      for (const c of stmt.contexts) collectExprReferences(ctx, c.expr);
      collectBlockReferences(ctx, stmt.body);
      break;
    case "ThrowStmt":
    case "YieldStmt":
      collectExprReferences(ctx, stmt.value);
      break;
    case "DeferStmt":
      collectReferences(ctx, stmt.body);
      break;
    case "TestDecl":
      if (stmt.withClause) collectExprReferences(ctx, stmt.withClause);
      collectBlockReferences(ctx, stmt.body);
      break;
  }
}

function collectBlockReferences(ctx: BuildContext, block: AST.Block): void {
  for (const stmt of block.statements) {
    collectReferences(ctx, stmt);
  }
}

function collectExprReferences(ctx: BuildContext, expr: AST.Expr): void {
  switch (expr.kind) {
    case "Identifier": {
      // Try to resolve this identifier
      const def = resolveIdentifier(ctx, expr.name);
      if (def) {
        ctx.symbols.addReference({ symbolId: def.id, loc: expr.loc });
      }
      break;
    }
    case "MemberExpr": {
      collectExprReferences(ctx, expr.object);
      // Resolve member based on object type (recursively handles chains like user.p.say_hello)
      const objType = expr.object.resolvedType;
      let typeName = objType ? getTypeName(ctx.env, objType) : null;
      
      // Fallback: if type is "any", try to infer from the object expression recursively
      if (!typeName) {
        typeName = inferTypeNameFromExpr(ctx, expr.object);
      }
      
      if (typeName) {
        const fieldDef = ctx.symbols.findMember(typeName, expr.property);
        if (fieldDef) {
          ctx.symbols.addReference({ symbolId: fieldDef.id, loc: expr.loc });
        }
      }
      break;
    }
    case "CallExpr":
      collectExprReferences(ctx, expr.callee);
      for (const arg of expr.args) {
        const argExpr = "kind" in arg ? arg : arg.value;
        collectExprReferences(ctx, argExpr);
      }
      break;
    case "BinaryExpr":
    case "PipeExpr":
      collectExprReferences(ctx, expr.left);
      collectExprReferences(ctx, expr.right);
      break;
    case "UnaryExpr":
      collectExprReferences(ctx, expr.operand);
      break;
    case "IndexExpr":
      collectExprReferences(ctx, expr.object);
      collectExprReferences(ctx, expr.index);
      if (expr.slice) {
        if (expr.slice.start) collectExprReferences(ctx, expr.slice.start);
        if (expr.slice.end) collectExprReferences(ctx, expr.slice.end);
        if (expr.slice.step) collectExprReferences(ctx, expr.slice.step);
      }
      break;
    case "IfExpr":
      collectExprReferences(ctx, expr.condition);
      collectExprReferences(ctx, expr.then);
      collectExprReferences(ctx, expr.else);
      break;
    case "MatchExpr":
      collectExprReferences(ctx, expr.value);
      for (const arm of expr.arms) {
        if (arm.guard) collectExprReferences(ctx, arm.guard);
        if (arm.body.kind === "Block") {
          collectBlockReferences(ctx, arm.body);
        } else {
          collectExprReferences(ctx, arm.body);
        }
      }
      break;
    case "LambdaExpr":
      if (expr.body.kind === "Block") {
        collectBlockReferences(ctx, expr.body);
      } else {
        collectExprReferences(ctx, expr.body);
      }
      break;
    case "ListExpr":
      for (const el of expr.elements) {
        if (el.kind === "SpreadElement") {
          collectExprReferences(ctx, el.expr);
        } else {
          collectExprReferences(ctx, el);
        }
      }
      break;
    case "MapExpr":
      for (const entry of expr.entries) {
        collectExprReferences(ctx, entry.key);
        collectExprReferences(ctx, entry.value);
      }
      break;
    case "TemplateLiteral":
      for (const part of expr.parts) {
        if (typeof part !== "string") {
          collectExprReferences(ctx, part.expr);
        }
      }
      break;
    case "RangeExpr":
      collectExprReferences(ctx, expr.start);
      collectExprReferences(ctx, expr.end);
      break;
    case "SpawnExpr":
    case "TypeAssertion":
    case "NullAssertion":
      collectExprReferences(ctx, expr.expr);
      break;
  }
}

function resolveIdentifier(ctx: BuildContext, name: string): SymbolDef | undefined {
  // Walk back through the scope chain: "A.B.C" -> "A.B" -> "A" -> global
  let scope = ctx.currentScope;
  while (scope) {
    const def = ctx.symbols.getDefinition(`${scope}.${name}`);
    if (def) return def;
    // Move to parent scope
    const lastDot = scope.lastIndexOf(".");
    scope = lastDot > 0 ? scope.slice(0, lastDot) : "";
  }
  // Try global scope
  return ctx.symbols.getDefinition(name);
}

// Recursively infer type name from any expression (handles chains like user.p)
function inferTypeNameFromExpr(ctx: BuildContext, expr: AST.Expr): string | null {
  // Identifier: look up variable definition
  if (expr.kind === "Identifier") {
    return inferTypeNameFromIdentifier(ctx, expr.name);
  }
  
  // Member expression: resolve the chain recursively
  if (expr.kind === "MemberExpr") {
    const objTypeName = inferTypeNameFromExpr(ctx, expr.object);
    if (objTypeName) {
      // Find the field's type in the object type
      return getFieldTypeName(ctx, objTypeName, expr.property);
    }
  }
  
  // Call expression on a member (e.g., user.get().field)
  if (expr.kind === "CallExpr" && expr.callee.kind === "MemberExpr") {
    const objTypeName = inferTypeNameFromExpr(ctx, expr.callee.object);
    if (objTypeName) {
      // Find the method's return type
      return getMethodReturnTypeName(ctx, objTypeName, expr.callee.property);
    }
  }
  
  return null;
}

// Try to infer type name from an identifier by looking at its definition
function inferTypeNameFromIdentifier(ctx: BuildContext, name: string): string | null {
  // Find the variable definition
  for (const stmt of ctx.program.body) {
    if (stmt.kind === "LetStmt" && stmt.pattern?.kind === "IdentifierPattern" && stmt.pattern.name === name) {
      return getTypeNameFromConstructor(stmt.value);
    }
    if (stmt.kind === "VarStmt" && stmt.name === name) {
      return getTypeNameFromConstructor(stmt.value);
    }
    // Also check inside functions
    if (stmt.kind === "FnDecl" && stmt.body && ctx.currentScope.startsWith(stmt.name)) {
      for (const s of stmt.body.statements) {
        if (s.kind === "LetStmt" && s.pattern?.kind === "IdentifierPattern" && s.pattern.name === name) {
          return getTypeNameFromConstructor(s.value);
        }
        if (s.kind === "VarStmt" && s.name === name) {
          return getTypeNameFromConstructor(s.value);
        }
      }
    }
  }
  return null;
}

// Extract type name from a constructor call expression
function getTypeNameFromConstructor(expr: AST.Expr): string | null {
  // Direct type constructor: Person("John")
  if (expr.kind === "CallExpr" && expr.callee.kind === "Identifier") {
    return expr.callee.name;
  }
  // Generic type constructor: Container[string]("hello")
  if (expr.kind === "CallExpr" && expr.callee.kind === "IndexExpr" && expr.callee.object.kind === "Identifier") {
    return expr.callee.object.name;
  }
  return null;
}

// Get the type name of a field in a type
function getFieldTypeName(ctx: BuildContext, typeName: string, fieldName: string): string | null {
  // Look up the type declaration in the program
  for (const stmt of ctx.program.body) {
    if (stmt.kind === "TypeDecl" && stmt.name === typeName) {
      for (const member of stmt.body.members) {
        if (member.kind === "FieldDecl" && member.name === fieldName) {
          // Get the type annotation
          if (member.type) {
            return getTypeNameFromAstType(member.type);
          }
          // If no type annotation but has default, infer from default
          if (member.defaultValue) {
            return getTypeNameFromConstructor(member.defaultValue);
          }
        }
      }
    }
  }
  return null;
}

// Get the return type name of a method
function getMethodReturnTypeName(ctx: BuildContext, typeName: string, methodName: string): string | null {
  for (const stmt of ctx.program.body) {
    if (stmt.kind === "TypeDecl" && stmt.name === typeName) {
      for (const member of stmt.body.members) {
        if (member.kind === "MethodDecl" && member.name === methodName) {
          if (member.returnType) {
            return getTypeNameFromAstType(member.returnType);
          }
        }
      }
    }
  }
  return null;
}

// Extract type name from AST type annotation
function getTypeNameFromAstType(type: AST.TypeExpr): string | null {
  if (type.kind === "NamedType") {
    return type.name;
  }
  if (type.kind === "GenericType") {
    return type.name;
  }
  return null;
}

// Get the type name for member lookup (handles ref, object, generic types)
function getTypeName(env: TypeEnvironment, type: Type): string | null {
  // Handle ref types (e.g., Hello[string] has kind: "ref", name: "Hello")
  if (type.kind === "ref") {
    return type.name;
  }
  // Handle object types with a name
  if (type.kind === "object" && (type as ObjectType).name) {
    return (type as ObjectType).name!;
  }
  // Handle optional types - unwrap and recurse
  if (type.kind === "optional") {
    return getTypeName(env, (type as any).inner);
  }
  // Try resolving if env can help
  const resolved = env.resolveType(type);
  if (resolved !== type) {
    // Avoid infinite recursion
    if (resolved.kind === "object" && (resolved as ObjectType).name) {
      return (resolved as ObjectType).name!;
    }
    if (resolved.kind === "ref") {
      return resolved.name;
    }
  }
  return null;
}
