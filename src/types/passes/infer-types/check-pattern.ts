// Pattern Checking - Validates patterns and binds pattern variables
import * as AST from "../../../parser/ast";
import type { Type, ObjectType } from "../../types";
import { Types, typeToString } from "../../types";
import { TypeErrors } from "../../../shared/errors";
import { astTypeToType, isAssignable } from "../../type-utils";
import type { InferContext } from "./context";
import { error } from "./context";

// Helper to resolve ref types
function resolve(type: Type, ctx: InferContext): Type {
  return type.kind === "ref" ? ctx.env.resolveType(type) : type;
}

// Get the literal type from a pattern value
function getLiteralType(value: unknown): Type {
  if (typeof value === "number") return Types.number;
  if (typeof value === "string") return Types.string;
  if (typeof value === "boolean") return Types.bool;
  if (value === null) return Types.null;
  return Types.any;
}

// Check if a type can match a literal
function canMatchLiteral(literalType: Type, expectedType: Type): boolean {
  if (expectedType.kind === "any" || expectedType.kind === literalType.kind) return true;
  if (expectedType.kind === "union") {
    return expectedType.types.some(t => canMatchLiteral(literalType, t));
  }
  if (expectedType.kind === "optional") {
    return literalType.kind === "null" || canMatchLiteral(literalType, expectedType.inner);
  }
  return false;
}

// Check if pattern type is compatible with expected type
function isPatternTypeCompatible(patternType: Type, expectedType: Type, ctx: InferContext): boolean {
  if (expectedType.kind === "any") return true;
  if (isAssignable(patternType, expectedType, ctx.env)) return true;
  if (expectedType.kind === "union") {
    return expectedType.types.some(t => isAssignable(patternType, t, ctx.env));
  }
  if (expectedType.kind === "optional") {
    return isPatternTypeCompatible(patternType, expectedType.inner, ctx);
  }
  return false;
}

// Check if a type is numeric (for range patterns)
function isNumeric(type: Type): boolean {
  if (type.kind === "number" || type.kind === "any") return true;
  if (type.kind === "union") return type.types.some(isNumeric);
  if (type.kind === "optional") return isNumeric(type.inner);
  return false;
}

// Main pattern validation and binding function
export function checkPattern(ctx: InferContext, pattern: AST.Pattern, expectedType: Type): void {
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
        ctx.env.define(pattern.name, Types.list(Types.any));
      }
      break;
    
    case "TypePattern": {
      const patternType = astTypeToType(pattern.type);
      if (!isPatternTypeCompatible(patternType, expectedType, ctx)) {
        const err = TypeErrors.incompatibleTypePattern(typeToString(patternType), typeToString(expectedType));
        error(ctx, err.message, pattern.loc, err.hint);
      }
      if (pattern.binding) ctx.env.define(pattern.binding, patternType);
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

// Handle object pattern validation
function handleObjectPattern(ctx: InferContext, pattern: AST.ObjectPattern, resolved: Type, expectedType: Type): void {
  // Maps can be destructured with object patterns
  if (resolved.kind === "map") {
    for (const prop of pattern.properties) {
      checkPattern(ctx, prop.pattern, (resolved as any).valueType);
    }
    return;
  }
  
  if (resolved.kind !== "object" && resolved.kind !== "any") {
    const err = TypeErrors.patternTypeMismatch("object", typeToString(expectedType));
    error(ctx, err.message, pattern.loc, err.hint);
    for (const prop of pattern.properties) checkPattern(ctx, prop.pattern, Types.any);
    return;
  }
  
  if (resolved.kind === "any") {
    for (const prop of pattern.properties) checkPattern(ctx, prop.pattern, Types.any);
    return;
  }
  
  const objType = resolved as ObjectType;
  for (const prop of pattern.properties) {
    const propType = objType.properties.find(p => p.name === prop.key);
    if (!propType) {
      const err = TypeErrors.unknownPatternProperty(prop.key, typeToString(expectedType));
      error(ctx, err.message, prop.pattern.loc ?? pattern.loc, err.hint);
      checkPattern(ctx, prop.pattern, Types.any);
    } else {
      checkPattern(ctx, prop.pattern, propType.type);
    }
  }
}

// Handle array pattern validation
function handleArrayPattern(ctx: InferContext, pattern: AST.ArrayPattern, resolved: Type, expectedType: Type): void {
  if (resolved.kind !== "list" && resolved.kind !== "tuple") {
    const err = TypeErrors.patternTypeMismatch("array", typeToString(expectedType));
    error(ctx, err.message, pattern.loc, err.hint);
    for (const el of pattern.elements) checkPattern(ctx, el, Types.any);
    return;
  }
  
  if (resolved.kind === "tuple") {
    const nonRest = pattern.elements.filter(e => e.kind !== "RestPattern");
    const hasRest = pattern.elements.some(e => e.kind === "RestPattern");
    
    if ((!hasRest && nonRest.length !== resolved.elements.length) ||
        (hasRest && nonRest.length > resolved.elements.length)) {
      const err = TypeErrors.tuplePatternLengthMismatch(resolved.elements.length, nonRest.length);
      error(ctx, err.message, pattern.loc, err.hint);
    }
    
    let idx = 0;
    for (const el of pattern.elements) {
      if (el.kind === "RestPattern") {
        const rest = resolved.elements.slice(idx);
        ctx.env.define(el.name, rest.length > 0 ? Types.list(Types.union(...rest)) : Types.list(Types.any));
      } else {
        checkPattern(ctx, el, idx < resolved.elements.length ? resolved.elements[idx]! : Types.any);
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

// Bind pattern variables with mutability support (used for var statements)
export function bindPattern(ctx: InferContext, pattern: AST.Pattern, type: Type, mutable: boolean = false): void {
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
        for (const prop of pattern.properties) bindPattern(ctx, prop.pattern, (resolved as any).valueType, mutable);
      } else if (resolved.kind === "object") {
        for (const prop of pattern.properties) {
          const propType = resolved.properties.find(p => p.name === prop.key);
          if (!propType) {
            const err = TypeErrors.unknownPatternProperty(prop.key, typeToString(type));
            error(ctx, err.message, prop.pattern.loc ?? pattern.loc, err.hint);
            bindPattern(ctx, prop.pattern, Types.any, mutable);
          } else {
            bindPattern(ctx, prop.pattern, propType.type, mutable);
          }
        }
      } else if (resolved.kind === "any") {
        for (const prop of pattern.properties) bindPattern(ctx, prop.pattern, Types.any, mutable);
      } else {
        const err = TypeErrors.patternTypeMismatch("object", typeToString(type));
        error(ctx, err.message, pattern.loc, err.hint);
        for (const prop of pattern.properties) bindPattern(ctx, prop.pattern, Types.any, mutable);
      }
      break;
      
    case "ArrayPattern":
      if (resolved.kind === "list") {
        for (const el of pattern.elements) {
          if (el.kind === "RestPattern") ctx.env.define(el.name, resolved, mutable);
          else bindPattern(ctx, el, resolved.elementType, mutable);
        }
      } else if (resolved.kind === "tuple") {
        let idx = 0;
        for (const el of pattern.elements) {
          if (el.kind === "RestPattern") {
            const rest = resolved.elements.slice(idx);
            ctx.env.define(el.name, Types.list(rest.length > 0 ? Types.union(...rest) : Types.any), mutable);
          } else {
            bindPattern(ctx, el, idx < resolved.elements.length ? resolved.elements[idx]! : Types.any, mutable);
            idx++;
          }
        }
      } else {
        const err = TypeErrors.patternTypeMismatch("array", typeToString(type));
        error(ctx, err.message, pattern.loc, err.hint);
        for (const el of pattern.elements) bindPattern(ctx, el, Types.any, mutable);
      }
      break;
      
    case "RestPattern":
      if (resolved.kind === "list") ctx.env.define(pattern.name, resolved, mutable);
      else {
        const err = TypeErrors.patternTypeMismatch("rest", typeToString(type));
        error(ctx, err.message, pattern.loc, err.hint);
        ctx.env.define(pattern.name, Types.list(Types.any), mutable);
      }
      break;
  }
}
