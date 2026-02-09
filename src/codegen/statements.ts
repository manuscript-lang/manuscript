// Statement Generators
import type * as AST from "../parser/ast";
import type { Ctx, GenOpts } from "./types";
import { emit, pushIndent, popIndent, tempVar, pushScope, popScope, addDefer, getTypeName } from "./types";
import { genExpr } from "./expressions";

// Forward declaration for mutual recursion with gen()
export type GenFn = (ctx: Ctx, node: AST.Expr | AST.Statement, opts: GenOpts) => string;
let _gen: GenFn;
export function setGen(fn: GenFn): void {
  _gen = fn;
}

// ============================================
// Pattern Generators
// ============================================

// Generate pattern for destructuring (let [x, y] = arr)
export function genPattern(pattern: AST.Pattern): string {
  switch (pattern.kind) {
    case "IdentifierPattern":
      return pattern.name;
    case "ArrayPattern": {
      const elements = pattern.elements.map(el => genPattern(el));
      return `[${elements.join(", ")}]`;
    }
    case "ObjectPattern": {
      const props = pattern.properties.map(p => {
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

// Generate match condition for a pattern
export function genPatternCondition(tv: string, pattern: AST.Pattern): string {
  switch (pattern.kind) {
    case "WildcardPattern":
      return "true";
    case "IdentifierPattern":
      return "true";
    case "LiteralPattern":
      return `${tv} === ${JSON.stringify(pattern.value)}`;
    case "TypePattern": {
      const typeName = pattern.type.kind === "NamedType" ? pattern.type.name : "Object";
      return `(${tv}?.__typename === "${typeName}" || ${tv} instanceof ${typeName})`;
    }
    case "RangePattern":
      return `${tv} >= ${pattern.start} && ${tv} <= ${pattern.end}`;
    case "ArrayPattern":
      return `Array.isArray(${tv})`;
    case "ObjectPattern":
      return `typeof ${tv} === "object" && ${tv} !== null`;
    default:
      return "true";
  }
}

// Generate match condition with optional guard
export function genMatchCondition(
  ctx: Ctx,
  tv: string,
  pattern: AST.Pattern,
  guard: AST.Expr | undefined,
  opts: GenOpts
): string {
  let condition = genPatternCondition(tv, pattern);

  if (guard) {
    if (pattern.kind === "IdentifierPattern") {
      condition = `${condition} && (((${pattern.name}) => (${genExpr(ctx, guard, opts)}))(${tv}))`;
    } else {
      condition = `${condition} && (${genExpr(ctx, guard, opts)})`;
    }
  }

  return condition;
}

// Generate pattern variable bindings
export function genPatternBindings(ctx: Ctx, tv: string, pattern: AST.Pattern): void {
  switch (pattern.kind) {
    case "IdentifierPattern":
      emit(ctx, `const ${pattern.name} = ${tv};`);
      break;
    case "TypePattern":
      if (pattern.binding) {
        emit(ctx, `const ${pattern.binding} = ${tv};`);
      }
      break;
    case "ArrayPattern":
      for (let i = 0; i < pattern.elements.length; i++) {
        const el = pattern.elements[i];
        if (!el) continue;
        if (el.kind === "IdentifierPattern") {
          emit(ctx, `const ${el.name} = ${tv}[${i}];`);
        } else if (el.kind === "RestPattern") {
          emit(ctx, `const ${el.name} = ${tv}.slice(${i});`);
        }
      }
      break;
    case "ObjectPattern":
      for (const prop of pattern.properties) {
        if (prop.pattern.kind === "IdentifierPattern") {
          emit(ctx, `const ${prop.pattern.name} = ${tv}.${prop.key};`);
        }
      }
      break;
  }
}

// ============================================
// Statement Generators
// ============================================

// Generate let statement
export function genLet(ctx: Ctx, stmt: AST.LetStmt, opts: GenOpts): void {
  const pattern = genPattern(stmt.pattern);
  const value = genExpr(ctx, stmt.value, opts);
  emit(ctx, `const ${pattern} = ${value};`);
}

// Generate var statement
export function genVar(ctx: Ctx, stmt: AST.VarStmt, opts: GenOpts): void {
  const value = genExpr(ctx, stmt.value, opts);
  emit(ctx, `let ${stmt.name} = ${value};`);
}

// Generate assignment statement
export function genAssign(ctx: Ctx, stmt: AST.AssignStmt, opts: GenOpts): void {
  const target = genExpr(ctx, stmt.target, opts);
  const value = genExpr(ctx, stmt.value, opts);
  emit(ctx, `${target} ${stmt.op} ${value};`);
}

// Generate if statement
export function genIf(ctx: Ctx, stmt: AST.IfStmt, opts: GenOpts): void {
  const cond = genExpr(ctx, stmt.condition, opts);
  const retOpts = opts.implicitReturn ? { ...opts, implicitReturn: true } : opts;
  emit(ctx, `if (${cond}) {`);
  pushIndent(ctx);

  if (stmt.then.kind === "Block") {
    genBlock(ctx, stmt.then, retOpts);
  } else if (opts.implicitReturn && stmt.then.kind === "ExprStmt") {
    const expr = stmt.then.expr.kind === "MapExpr"
      ? `(${genExpr(ctx, stmt.then.expr, opts)})`
      : genExpr(ctx, stmt.then.expr, opts);
    emit(ctx, `return ${expr};`);
  } else {
    _gen(ctx, stmt.then, opts);
  }

  popIndent(ctx);

  for (const elif of stmt.elseIfs) {
    const elifCond = genExpr(ctx, elif.condition, opts);
    emit(ctx, `} else if (${elifCond}) {`);
    pushIndent(ctx);
    genBlock(ctx, elif.body, retOpts);
    popIndent(ctx);
  }

  if (stmt.else) {
    emit(ctx, "} else {");
    pushIndent(ctx);
    genBlock(ctx, stmt.else, retOpts);
    popIndent(ctx);
  }

  emit(ctx, "}");
}

// Generate for statement
export function genFor(ctx: Ctx, stmt: AST.ForStmt, opts: GenOpts): void {
  // Loop bodies never have implicit return
  const loopOpts = { ...opts, implicitReturn: false };

  if (!stmt.pattern || !stmt.iterable) {
    // Infinite loop
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

// Generate match statement
export function genMatch(ctx: Ctx, stmt: AST.MatchStmt, opts: GenOpts): void {
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
      genBlock(ctx, arm.body, opts.implicitReturn ? { ...opts, implicitReturn: true } : opts);
    } else {
      const expr = genExpr(ctx, arm.body as AST.Expr, opts);
      emit(ctx, opts.implicitReturn ? `return ${expr};` : `${expr};`);
    }

    popIndent(ctx);
  }

  emit(ctx, "}");
}

// Generate return statement
export function genReturn(ctx: Ctx, stmt: AST.ReturnStmt, opts: GenOpts): void {
  if (stmt.value) {
    emit(ctx, `return ${genExpr(ctx, stmt.value, opts)};`);
  } else {
    emit(ctx, "return;");
  }
}

// Generate yield statement
export function genYield(ctx: Ctx, stmt: AST.YieldStmt, opts: GenOpts): void {
  emit(ctx, `yield ${genExpr(ctx, stmt.value, opts)};`);
}

// Generate defer statement
export function genDefer(ctx: Ctx, stmt: AST.DeferStmt): void {
  addDefer(ctx, stmt.body);
}

// Generate try statement
export function genTry(ctx: Ctx, stmt: AST.TryStmt, opts: GenOpts): void {
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

// Generate throw statement
export function genThrow(ctx: Ctx, stmt: AST.ThrowStmt, opts: GenOpts): void {
  const value = genExpr(ctx, stmt.value, opts);
  emit(ctx, `throw ${value};`);
}

// Generate with statement
export function genWith(ctx: Ctx, stmt: AST.WithStmt, opts: GenOpts): void {
  emit(ctx, "{");
  pushIndent(ctx);
  pushScope(ctx);

  emit(ctx, "__ms_runtime.__pushContext();");

  const ctxNames: string[] = [];
  for (const ctxBinding of stmt.contexts) {
    const expr = genExpr(ctx, ctxBinding.expr, opts);

    let name: string;
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
      // Register the context type (no inheritance chain with Go-style embedding)
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
    _gen(ctx, defer, opts);
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

// Generate expression statement
export function genExprStmt(ctx: Ctx, stmt: AST.ExprStmt, opts: GenOpts): void {
  if (stmt.expr.kind === "MapExpr") {
    emit(ctx, `(${genExpr(ctx, stmt.expr, opts)});`);
  } else {
    emit(ctx, `${genExpr(ctx, stmt.expr, opts)};`);
  }
}

// Generate a block of statements
export function genBlock(ctx: Ctx, block: AST.Block, opts: GenOpts): void {
  const stmts = block.statements;
  for (let i = 0; i < stmts.length; i++) {
    const stmt = stmts[i];
    const isLast = i === stmts.length - 1;

    if (isLast && opts.implicitReturn && stmt) {
      if (stmt.kind === "ExprStmt") {
        const expr = stmt.expr.kind === "MapExpr"
          ? `(${genExpr(ctx, stmt.expr, opts)})`
          : genExpr(ctx, stmt.expr, opts);
        emit(ctx, `return ${expr};`);
        continue;
      }
      if (stmt.kind === "MatchStmt") {
        genMatch(ctx, stmt, opts);
        continue;
      }
      if (stmt.kind === "IfStmt") {
        genIf(ctx, stmt, opts);
        continue;
      }
      if (stmt.kind === "WithStmt") {
        genWith(ctx, stmt, { ...opts, implicitReturn: true });
        continue;
      }
    }

    // Non-last statements should never have implicit return
    if (stmt) _gen(ctx, stmt, { ...opts, implicitReturn: false });
  }
}
