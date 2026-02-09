// Expression Generators
import type * as AST from "../parser/ast";
import type { Ctx, GenOpts } from "./types";
import { emit, pushIndent, popIndent, tempVar, isTypeConstructor, getParamOrder } from "./types";
import { STDLIB_FUNCTIONS, EXTERN_TYPES, PRIMITIVE_EXTERN_TYPES, isStdlibExternType } from "../builtin";
import type { Type, ListType, MapType } from "../types/types";
import { typeToString } from "../types/types";

// Forward declaration for mutual recursion
export type GenFn = (ctx: Ctx, node: AST.Expr | AST.Statement, opts: GenOpts) => string;
let _gen: GenFn;
export function setGen(fn: GenFn): void {
  _gen = fn;
}
function gen(ctx: Ctx, node: AST.Expr | AST.Statement, opts: GenOpts): string {
  return _gen(ctx, node, opts);
}

// Main expression dispatcher
export function genExpr(ctx: Ctx, expr: AST.Expr, opts: GenOpts): string {
  switch (expr.kind) {
    case "Literal": return genLiteral(expr);
    case "Identifier": return genIdentifier(expr, opts);
    case "BinaryExpr": return genBinary(ctx, expr, opts);
    case "UnaryExpr": return genUnary(ctx, expr, opts);
    case "CallExpr": return genCall(ctx, expr, opts);
    case "IndexExpr": return genIndex(ctx, expr, opts);
    case "MemberExpr": return genMember(ctx, expr, opts);
    case "PipeExpr": return genPipe(ctx, expr, opts);
    case "LambdaExpr": return genLambda(ctx, expr, opts);
    case "IfExpr": return genIfExpr(ctx, expr, opts);
    case "MatchExpr": return genMatchExpr(ctx, expr, opts);
    case "ListExpr": return genList(ctx, expr, opts);
    case "SetExpr": return genSet(ctx, expr, opts);
    case "MapExpr": return genMap(ctx, expr, opts);
    case "TemplateLiteral": return genTemplate(ctx, expr, opts);
    case "SpawnExpr": return genSpawn(ctx, expr, opts);
    case "IsExpr": return genIsExpr(ctx, expr, opts);
    case "TypeAssertion": return genExpr(ctx, expr.expr, opts);
    case "NullAssertion": return genExpr(ctx, expr.expr, opts);
    case "RangeExpr": return genRange(ctx, expr, opts);
  }
}

const IS_PLAIN_OBJECT =
  (x: string) => `(typeof ${x} === "object" && ${x} !== null && !Array.isArray(${x}) && !(${x} instanceof Set))`;

function getTypeArgsLiteralFromIndexExpr(indexExpr: AST.IndexExpr): string | null {
  const all = [indexExpr.index, ...(indexExpr.typeArgs ?? [])];
  const names = all.map((e): string | null => (e.kind === "Identifier" ? e.name : null));
  if (names.some(n => n === null)) return null;
  return JSON.stringify(names as string[]);
}

function typeExprToRuntimeTag(t: AST.TypeExpr): string {
  switch (t.kind) {
    case "NamedType": return t.name;
    case "GenericType": return t.args.length ? `${t.name}[${t.args.map(typeExprToRuntimeTag).join(",")}]` : t.name;
    case "OptionalType": return typeExprToRuntimeTag(t.inner);
    case "ListType": return `list[${typeExprToRuntimeTag(t.elementType)}]`;
    case "MapType": return `map[${typeExprToRuntimeTag(t.keyType)},${typeExprToRuntimeTag(t.valueType)}]`;
    case "UnionType": return t.types.map(typeExprToRuntimeTag).join("|");
    case "FunctionType": return "function";
    default: return "unknown";
  }
}

function typeToRuntimeTag(t: Type): string {
  switch (t.kind) {
    case "number":
    case "string":
    case "bool":
    case "null":
    case "bytes":
    case "never":
    case "unknown":
    case "void":
      return t.kind;
    case "list":
      return `list[${typeToRuntimeTag((t as ListType).elementType)}]`;
    case "map": {
      const m = t as MapType;
      return `map[${typeToRuntimeTag(m.keyType)},${typeToRuntimeTag(m.valueType)}]`;
    }
    case "set":
      return `set[${typeToRuntimeTag((t as { elementType: Type }).elementType)}]`;
    case "optional":
      return typeToRuntimeTag((t as { inner: Type }).inner);
    case "ref": {
      const r = t as { name: string; args?: Type[] };
      return r.args?.length ? `${r.name}[${r.args.map(typeToRuntimeTag).join(",")}]` : r.name;
    }
    case "generic": {
      const g = t as { base: Type; args: Type[] };
      return `${typeToRuntimeTag(g.base)}[${g.args.map(typeToRuntimeTag).join(",")}]`;
    }
    default:
      return typeToString(t).replace(/, /g, ",");
  }
}

function typeContainsTypeVar(t: Type): boolean {
  if (t.kind === "typevar") return true;
  if (t.kind === "list") return typeContainsTypeVar((t as ListType).elementType);
  if (t.kind === "map") {
    const m = t as MapType;
    return typeContainsTypeVar(m.keyType) || typeContainsTypeVar(m.valueType);
  }
  if (t.kind === "optional" || t.kind === "ref" || t.kind === "generic") {
    const g = t as { inner?: Type; args?: Type[]; base?: Type };
    if (g.inner && typeContainsTypeVar(g.inner)) return true;
    if (g.args?.some(a => typeContainsTypeVar(a))) return true;
    if (g.base && typeContainsTypeVar(g.base)) return true;
  }
  return false;
}

function getRuntimeTypeArgs(t: Type): string[] | null {
  if (typeContainsTypeVar(t)) return null;
  if (t.kind === "list") return [typeToRuntimeTag((t as ListType).elementType)];
  if (t.kind === "map") {
    const m = t as MapType;
    return [typeToRuntimeTag(m.keyType), typeToRuntimeTag(m.valueType)];
  }
  if (t.kind === "ref") {
    const r = t as { name: string; args?: Type[] };
    if (r.args?.length) return r.args.map(typeToRuntimeTag);
    return null;
  }
  if (t.kind === "generic") {
    const g = t as { base: Type; args: Type[] };
    return g.args.map(typeToRuntimeTag);
  }
  return null;
}

function genIsTypeCheck(leftStr: string, typeExpr: AST.TypeExpr): string {
  switch (typeExpr.kind) {
    case "NamedType": {
      const name = typeExpr.name;
      if (name === "string") return `typeof ${leftStr} === "string"`;
      if (name === "number") return `typeof ${leftStr} === "number"`;
      if (name === "bool") return `typeof ${leftStr} === "boolean"`;
      if (name === "null") return `${leftStr} === null`;
      if (name === "bytes") return `(${leftStr} instanceof Uint8Array || (typeof ${leftStr} === "object" && ${leftStr} !== null && ${leftStr}.constructor?.name === "Buffer"))`;
      if (name === "map") return `((${leftStr} instanceof Map) || ${IS_PLAIN_OBJECT(leftStr)})`;
      if (name === "list") return `Array.isArray(${leftStr})`;
      if (name === "set") return `(${leftStr} instanceof Set)`;
      return `(${leftStr}?.__typename === "${name}")`;
    }
    case "GenericType": {
      const name = typeExpr.name;
      const args = typeExpr.args;
      if (name === "list") {
        const base = `Array.isArray(${leftStr})`;
        if (args.length > 0) {
          const typeArgsJson = JSON.stringify(args.map(typeExprToRuntimeTag));
          return `(${base} && (!${leftStr}.__typeArgs || JSON.stringify(${leftStr}.__typeArgs) === ${JSON.stringify(typeArgsJson)}))`;
        }
        return base;
      }
      if (name === "map") {
        const base = `((${leftStr} instanceof Map) || ${IS_PLAIN_OBJECT(leftStr)})`;
        if (args.length >= 2) {
          const typeArgsJson = JSON.stringify(args.map(typeExprToRuntimeTag));
          return `(${base} && (!${leftStr}.__typeArgs || JSON.stringify(${leftStr}.__typeArgs) === ${JSON.stringify(typeArgsJson)}))`;
        }
        return base;
      }
      if (name === "set") return `(${leftStr} instanceof Set)`;
      if (args.length > 0) {
        const typeArgsJson = JSON.stringify(args.map(typeExprToRuntimeTag));
        return `(${leftStr}?.__typename === "${name}" && ${leftStr}.__typeArgs && JSON.stringify(${leftStr}.__typeArgs) === ${JSON.stringify(typeArgsJson)})`;
      }
      return `(${leftStr}?.__typename === "${name}")`;
    }
    case "OptionalType": {
      const inner = genIsTypeCheck(leftStr, typeExpr.inner);
      return `(${leftStr} === null || ${inner})`;
    }
    case "ListType": {
      const base = `Array.isArray(${leftStr})`;
      const tag = typeExprToRuntimeTag(typeExpr.elementType);
      const typeArgsJson = JSON.stringify([tag]);
      return `(${base} && (!${leftStr}.__typeArgs || JSON.stringify(${leftStr}.__typeArgs) === ${typeArgsJson}))`;
    }
    case "MapType": {
      const base = `((${leftStr} instanceof Map) || ${IS_PLAIN_OBJECT(leftStr)})`;
      const typeArgsJson = JSON.stringify([typeExprToRuntimeTag(typeExpr.keyType), typeExprToRuntimeTag(typeExpr.valueType)]);
      return `(${base} && (!${leftStr}.__typeArgs || JSON.stringify(${leftStr}.__typeArgs) === ${typeArgsJson}))`;
    }
    case "UnionType":
      return typeExpr.types.map(t => genIsTypeCheck(leftStr, t)).join(" || ");
    case "FunctionType":
      return `(typeof ${leftStr} === "function")`;
    default:
      return "false";
  }
}

function genIsExpr(ctx: Ctx, node: AST.IsExpr, opts: GenOpts): string {
  const left = genExpr(ctx, node.expr, opts);
  return `(${genIsTypeCheck(left, node.type)})`;
}

export function genLiteral(node: AST.Literal): string {
  if (node.value === null) return "null";
  if (typeof node.value === "string") return JSON.stringify(node.value);
  if (typeof node.value === "boolean") return node.value ? "true" : "false";
  return String(node.value);
}

export function genIdentifier(node: AST.Identifier, opts: GenOpts): string {
  // Don't prefix type names (used as constructors) - they're global
  if (isTypeConstructor(node)) {
    return node.name;
  }
  // Use self.field for factory function pattern, this.field for methods
  if (opts.classFields?.has(node.name)) {
    const prefix = opts.selfVar || "this";
    return `${prefix}.${node.name}`;
  }
  return node.name;
}

export function genBinary(ctx: Ctx, node: AST.BinaryExpr, opts: GenOpts): string {
  const left = genExpr(ctx, node.left, opts);
  const right = genExpr(ctx, node.right, opts);

  switch (node.op) {
    case "and": return `(${left} && ${right})`;
    case "or": return `(${left} || ${right})`;
    case "^": return `Math.pow(${left}, ${right})`;
    case "??": return `(${left} ?? ${right})`;
    default: return `(${left} ${node.op} ${right})`;
  }
}

export function genUnary(ctx: Ctx, node: AST.UnaryExpr, opts: GenOpts): string {
  const operand = genExpr(ctx, node.operand, opts);
  if (node.op === "not") return `!${operand}`;
  return `${node.op}${operand}`;
}

export function genCall(ctx: Ctx, node: AST.CallExpr, opts: GenOpts): string {
  const calleeExpr = node.callee;
  const calleeResolved = (calleeExpr as AST.BaseNode).resolvedType;
  const isGenericFunctionCall = calleeExpr.kind === "IndexExpr" && calleeResolved?.kind === "function";
  let callee = isGenericFunctionCall
    ? genExpr(ctx, calleeExpr.object, opts)
    : genExpr(ctx, calleeExpr, opts);

  // Prefix builtin functions (unless it's a class method shadowing the builtin)
  if (node.callee.kind === "Identifier" && 
      STDLIB_FUNCTIONS.has(node.callee.name) &&
      !opts.classFields?.has(node.callee.name)) {
    callee = `__ms_runtime.${node.callee.name}`;
  }

  // Handle generic constructors like UserType[T](...)
  if (node.callee.kind === "IndexExpr" && node.callee.object.kind === "Identifier") {
    const baseName = node.callee.object.name;
    const args = genCallArgs(ctx, node.args, opts);
    const isExtern = EXTERN_TYPES.has(baseName) || isStdlibExternType(baseName);
    if (isExtern && !PRIMITIVE_EXTERN_TYPES.has(baseName)) {
      return `new __ms_runtime.${baseName}(${args})`;
    }
    if (isTypeConstructor(node.callee.object) || ctx.typeFields.has(baseName)) {
      const callType = (node as AST.CallExpr & { resolvedType?: Type }).resolvedType;
      const typeArgs = callType ? getRuntimeTypeArgs(callType) : null;
      const typeArgsLit = typeArgs ? JSON.stringify(typeArgs) : getTypeArgsLiteralFromIndexExpr(node.callee);
      return typeArgsLit ? `${baseName}(${args}, ${typeArgsLit})` : `${baseName}(${args})`;
    }
  }

  // Extern type constructors (e.g. Context(...))
  // Primitive types (string, list, map, set) are never constructors
  if (node.callee.kind === "Identifier" &&
      (EXTERN_TYPES.has(node.callee.name) || isStdlibExternType(node.callee.name)) &&
      !STDLIB_FUNCTIONS.has(node.callee.name) &&
      !PRIMITIVE_EXTERN_TYPES.has(node.callee.name)) {
    const args = genCallArgs(ctx, node.args, opts);
    return `new __ms_runtime.${node.callee.name}(${args})`;
  }

  // Set methods values/entries/keys return iterators in JS; we need lists
  if (node.callee.kind === "MemberExpr" && node.args.length === 0) {
    const objType = node.callee.object.resolvedType;
    if (objType?.kind === "set" && ["values", "entries", "keys"].includes(node.callee.property)) {
      const obj = genExpr(ctx, node.callee.object, opts);
      const method = node.callee.property;
      return `Array.from(${obj}.${method}())`;
    }
  }

  // Get param order from callee's resolved type for user-defined functions and types
  const paramOrder = getParamOrder(node.callee);
  const args = genCallArgs(ctx, node.args, opts, paramOrder);

  const callType = (node as AST.CallExpr & { resolvedType?: Type }).resolvedType;
  const typeArgs = callType ? getRuntimeTypeArgs(callType) : null;
  const typeArgsSuffix = typeArgs ? `, ${JSON.stringify(typeArgs)}` : "";

  if (isTypeConstructor(node.callee)) {
    return `${callee}(${args}${typeArgsSuffix})`;
  }
  if (node.callee.kind === "Identifier" && ctx.typeFields.has(node.callee.name)) {
    return `${callee}(${args}${typeArgsSuffix})`;
  }

  // Implicit await for all function calls
  return `(await ${callee}(${args}))`;
}

function genCallArgs(
  ctx: Ctx,
  args: (AST.Expr | { name: string; value: AST.Expr })[],
  opts: GenOpts,
  paramOrder?: string[]
): string {
  const hasNamed = args.some((a) => "name" in a && "value" in a);

  if (hasNamed && paramOrder && paramOrder.length > 0) {
    const byName = new Map<string, AST.Expr>();
    const positional: AST.Expr[] = [];
    for (const a of args) {
      if ("name" in a && "value" in a) {
        byName.set(a.name, a.value);
      } else {
        positional.push(a as AST.Expr);
      }
    }
    let posIdx = 0;
    const ordered: (AST.Expr | null)[] = paramOrder.map((name): AST.Expr | null => {
      if (byName.has(name)) return byName.get(name)!;
      if (posIdx < positional.length) return positional[posIdx++]!;
      return null;
    });
    // Find the last non-null index to trim trailing undefined args
    let lastProvided = ordered.length - 1;
    while (lastProvided >= 0 && ordered[lastProvided] === null) {
      lastProvided--;
    }
    // Generate args, using 'undefined' for missing intermediate params
    const result = ordered.slice(0, lastProvided + 1).map((e) => 
      e === null ? "undefined" : genExpr(ctx, e, opts)
    );
    return result.join(", ");
  }

  if (hasNamed) {
    const parts: string[] = [];
    for (const arg of args) {
      if ("name" in arg && "value" in arg) {
        parts.push(`${arg.name}: ${genExpr(ctx, arg.value, opts)}`);
      } else {
        parts.push(genExpr(ctx, arg as AST.Expr, opts));
      }
    }
    return `{ ${parts.join(", ")} }`;
  }

  return args.map((a) => genExpr(ctx, a as AST.Expr, opts)).join(", ");
}

export function genIndex(ctx: Ctx, node: AST.IndexExpr, opts: GenOpts): string {
  const obj = genExpr(ctx, node.object, opts);

  if (node.slice) {
    const start = node.slice.start ? genExpr(ctx, node.slice.start, opts) : "0";
    const end = node.slice.end ? genExpr(ctx, node.slice.end, opts) : "";
    if (node.optional) return `${obj}?.slice(${start}, ${end})`;
    return `${obj}.slice(${start}, ${end})`;
  }

  const index = genExpr(ctx, node.index, opts);
  if (node.optional) return `${obj}?.[${index}]`;
  return `${obj}[${index}]`;
}

export function genMember(ctx: Ctx, node: AST.MemberExpr, opts: GenOpts): string {
  const obj = genExpr(ctx, node.object, opts);
  if (node.optional) return `${obj}?.${node.property}`;
  return `${obj}.${node.property}`;
}

export function genPipe(ctx: Ctx, node: AST.PipeExpr, opts: GenOpts): string {
  const left = genExpr(ctx, node.left, opts);
  const right = node.right;

  if (right.kind === "CallExpr") {
    let callee = genExpr(ctx, right.callee, opts);
    if (right.callee.kind === "Identifier" && STDLIB_FUNCTIONS.has(right.callee.name)) {
      callee = `__ms_runtime.${right.callee.name}`;
    }
    const args = [left, ...right.args.map(a => genExpr(ctx, a as AST.Expr, opts))];
    return `(await ${callee}(${args.join(", ")}))`;
  } else if (right.kind === "Identifier") {
    const fnName = STDLIB_FUNCTIONS.has(right.name) ? `__ms_runtime.${right.name}` : right.name;
    return `(await ${fnName}(${left}))`;
  }

  return `(await (${genExpr(ctx, right, opts)})(${left}))`;
}

export function genLambda(ctx: Ctx, node: AST.LambdaExpr, opts: GenOpts): string {
  const params = node.params.map(p => {
    let param = p.name;
    if (p.rest) param = `...${param}`;
    if (p.defaultValue) param += ` = ${genExpr(ctx, p.defaultValue, opts)}`;
    return param;
  }).join(", ");

  if (node.body.kind === "Block") {
    const bodyLines: string[] = [];
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
    return `async (${params}) => {\n${bodyLines.join("\n")}\n${indentStr}}`;
  }

  return `async (${params}) => ${genExpr(ctx, node.body as AST.Expr, opts)}`;
}

export function genIfExpr(ctx: Ctx, node: AST.IfExpr, opts: GenOpts): string {
  const cond = genExpr(ctx, node.condition, opts);
  const then = genExpr(ctx, node.then, opts);
  const elseExpr = genExpr(ctx, node.else, opts);
  return `(${cond} ? ${then} : ${elseExpr})`;
}

export function genMatchExpr(ctx: Ctx, node: AST.MatchExpr, opts: GenOpts): string {
  const value = genExpr(ctx, node.value, opts);
  const tv = tempVar(ctx, "_m");

  let code = `((_${tv}) => {\n`;

  for (const arm of node.arms) {
    const condition = genPatternCondition(`_${tv}`, arm.pattern);
    code += `  if (${condition}) {\n`;

    if (arm.pattern.kind === "IdentifierPattern") {
      code += `    const ${arm.pattern.name} = _${tv};\n`;
    }

    if (arm.body.kind === "Block") {
      code += `    // block body\n`;
    } else {
      code += `    return ${genExpr(ctx, arm.body as AST.Expr, opts)};\n`;
    }

    code += `  }\n`;
  }

  code += `})(${value})`;
  return code;
}

// Pattern condition for match expressions (simplified version, full in patterns.ts)
function genPatternCondition(tempVar: string, pattern: AST.Pattern): string {
  switch (pattern.kind) {
    case "WildcardPattern": return "true";
    case "IdentifierPattern": return "true";
    case "LiteralPattern": return `${tempVar} === ${JSON.stringify(pattern.value)}`;
    case "TypePattern": {
      const typeName = pattern.type.kind === "NamedType" ? pattern.type.name : "Object";
      // Use __typename for Manuscript types, fallback to instanceof for external types
      return `(${tempVar}?.__typename === "${typeName}" || ${tempVar} instanceof ${typeName})`;
    }
    case "RangePattern": return `${tempVar} >= ${pattern.start} && ${tempVar} <= ${pattern.end}`;
    case "ArrayPattern": return `Array.isArray(${tempVar})`;
    case "ObjectPattern": return `typeof ${tempVar} === "object" && ${tempVar} !== null`;
    default: return "true";
  }
}

export function genList(ctx: Ctx, node: AST.ListExpr, opts: GenOpts): string {
  const elements = node.elements.map(el => {
    if (el.kind === "SpreadElement") {
      return `...${genExpr(ctx, el.expr, opts)}`;
    }
    return genExpr(ctx, el, opts);
  });
  const arr = elements.length === 0 ? "[]" : `[${elements.join(", ")}]`;
  const rt = (node as AST.ListExpr & { resolvedType?: Type }).resolvedType;
  const typeArgs = rt ? getRuntimeTypeArgs(rt) : null;
  if (typeArgs) {
    const inner = `const _a=${arr};Object.defineProperty(_a,"__typeArgs",{value:${JSON.stringify(typeArgs)},enumerable:false});return _a`;
    return opts.syncContext ? `(function(){${inner}})()` : `(await (async function(){${inner}})())`;
  }
  return arr;
}

export function genSet(ctx: Ctx, node: AST.SetExpr, opts: GenOpts): string {
  if (node.elements.length === 0) return "new Set()";
  const inner = node.elements.map(el => genExpr(ctx, el, opts)).join(", ");
  return `new Set([${inner}])`;
}

export function genMap(ctx: Ctx, node: AST.MapExpr, opts: GenOpts): string {
  if (node.entries.length === 0) {
    const rt = (node as AST.MapExpr & { resolvedType?: Type }).resolvedType;
    const typeArgs = rt ? getRuntimeTypeArgs(rt) : null;
    if (typeArgs) {
      const inner = `const _m=Object.create(null);Object.defineProperty(_m,"__typeArgs",{value:${JSON.stringify(typeArgs)},enumerable:false});return _m`;
      return opts.syncContext ? `(function(){${inner}})()` : `(await (async function(){${inner}})())`;
    }
    return "Object.create(null)";
  }

  const literalParts: string[] = [];
  const spreadExprs: string[] = [];
  for (const entry of node.entries) {
    if (entry.spread) {
      spreadExprs.push(genExpr(ctx, entry.key, opts));
    } else {
      const key = entry.key.kind === "Identifier"
        ? entry.key.name
        : `[${genExpr(ctx, entry.key, opts)}]`;
      const value = genExpr(ctx, entry.value, opts);
      literalParts.push(`${key}: ${value}`);
    }
  }
  const sources = [...spreadExprs];
  if (literalParts.length > 0) sources.push(`{ ${literalParts.join(", ")} }`);
  const mapExpr = sources.length === 0 ? "Object.create(null)" : `Object.assign(Object.create(null), ${sources.join(", ")})`;
  const rt = (node as AST.MapExpr & { resolvedType?: Type }).resolvedType;
  const typeArgs = rt ? getRuntimeTypeArgs(rt) : null;
  if (typeArgs) {
    const inner = `const _m=${mapExpr};Object.defineProperty(_m,"__typeArgs",{value:${JSON.stringify(typeArgs)},enumerable:false});return _m`;
    return opts.syncContext ? `(function(){${inner}})()` : `(await (async function(){${inner}})())`;
  }
  return mapExpr;
}

export function genTemplate(ctx: Ctx, node: AST.TemplateLiteral, opts: GenOpts): string {
  const parts = node.parts.map(p => {
    if (typeof p === "string") return JSON.stringify(p);
    // Use to_str for interpolated expressions to handle null-prototype objects
    return `__ms_runtime.to_str(${genExpr(ctx, p.expr, opts)})`;
  });
  return parts.length === 1 ? parts[0]! : `(${parts.join(" + ")})`;
}

export function genSpawn(ctx: Ctx, node: AST.SpawnExpr, opts: GenOpts): string {
  const inner = genExpr(ctx, node.expr, opts);
  return `__ms_runtime.spawn(async () => ${inner})`;
}

export function genRange(ctx: Ctx, node: AST.RangeExpr, opts: GenOpts): string {
  const start = genExpr(ctx, node.start, opts);
  const end = genExpr(ctx, node.end, opts);
  return `__ms_runtime.range(${start}, ${end}, ${node.inclusive})`;
}
