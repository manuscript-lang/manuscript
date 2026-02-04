// Pattern Generators - for destructuring and match statements
import type * as AST from "../parser/ast";
import type { Ctx, GenOpts } from "./types";
import { emit } from "./types";
import { genExpr } from "./expressions";

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
export function genPatternCondition(tempVar: string, pattern: AST.Pattern): string {
  switch (pattern.kind) {
    case "WildcardPattern":
      return "true";
    case "IdentifierPattern":
      return "true";
    case "LiteralPattern":
      return `${tempVar} === ${JSON.stringify(pattern.value)}`;
    case "TypePattern": {
      const typeName = pattern.type.kind === "NamedType" ? pattern.type.name : "Object";
      // Use __typename for Manuscript types (factory functions), fallback to instanceof for external types
      return `(${tempVar}?.__typename === "${typeName}" || ${tempVar} instanceof ${typeName})`;
    }
    case "RangePattern":
      return `${tempVar} >= ${pattern.start} && ${tempVar} <= ${pattern.end}`;
    case "ArrayPattern":
      return `Array.isArray(${tempVar})`;
    case "ObjectPattern":
      return `typeof ${tempVar} === "object" && ${tempVar} !== null`;
    default:
      return "true";
  }
}

// Generate match condition with optional guard
export function genMatchCondition(
  ctx: Ctx,
  tempVar: string,
  pattern: AST.Pattern,
  guard: AST.Expr | undefined,
  opts: GenOpts
): string {
  let condition = genPatternCondition(tempVar, pattern);

  if (guard) {
    if (pattern.kind === "IdentifierPattern") {
      // Bind variable in guard scope
      condition = `${condition} && (((${pattern.name}) => (${genExpr(ctx, guard, opts)}))(${tempVar}))`;
    } else {
      condition = `${condition} && (${genExpr(ctx, guard, opts)})`;
    }
  }

  return condition;
}

// Generate pattern variable bindings
export function genPatternBindings(ctx: Ctx, tempVar: string, pattern: AST.Pattern): void {
  switch (pattern.kind) {
    case "IdentifierPattern":
      emit(ctx, `const ${pattern.name} = ${tempVar};`);
      break;
    case "TypePattern":
      if (pattern.binding) {
        emit(ctx, `const ${pattern.binding} = ${tempVar};`);
      }
      break;
    case "ArrayPattern":
      for (let i = 0; i < pattern.elements.length; i++) {
        const el = pattern.elements[i];
        if (!el) continue;
        if (el.kind === "IdentifierPattern") {
          emit(ctx, `const ${el.name} = ${tempVar}[${i}];`);
        } else if (el.kind === "RestPattern") {
          emit(ctx, `const ${el.name} = ${tempVar}.slice(${i});`);
        }
      }
      break;
    case "ObjectPattern":
      for (const prop of pattern.properties) {
        if (prop.pattern.kind === "IdentifierPattern") {
          emit(ctx, `const ${prop.pattern.name} = ${tempVar}.${prop.key};`);
        }
      }
      break;
  }
}
