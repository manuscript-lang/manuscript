// Pattern Checking - Validates patterns and binds pattern variables
import * as AST from "../../../parser/ast";
import type { Type } from "../../types";
import { Types } from "../../types";
import { TypeErrors } from "../../../shared/errors";
import { astTypeToType } from "../../type-utils";
import type { InferContext } from "./context";
import { error } from "./context";

// Check a pattern against an expected type, defining bindings in the environment
export function checkPattern(ctx: InferContext, pattern: AST.Pattern, expectedType: Type): void {
  switch (pattern.kind) {
    case "IdentifierPattern":
      ctx.env.define(pattern.name, expectedType);
      break;
    case "LiteralPattern":
      // Check literal is compatible with expected type (no bindings)
      break;
    case "ObjectPattern":
      if (expectedType.kind === "object") {
        for (const prop of pattern.properties) {
          const propType = expectedType.properties.find(p => p.name === prop.key);
          if (propType) {
            checkPattern(ctx, prop.pattern, propType.type);
          }
        }
      }
      break;
    case "ArrayPattern":
      if (expectedType.kind === "list" || expectedType.kind === "tuple") {
        const elementType = expectedType.kind === "list"
          ? expectedType.elementType
          : Types.union(...expectedType.elements);
        for (const el of pattern.elements) {
          checkPattern(ctx, el, elementType);
        }
      }
      break;
    case "RestPattern":
      if (expectedType.kind === "list") {
        ctx.env.define(pattern.name, expectedType);
      }
      break;
    case "TypePattern":
      if (pattern.binding) {
        const narrowedType = astTypeToType(pattern.type);
        ctx.env.define(pattern.binding, narrowedType);
      }
      break;
    case "RangePattern":
    case "WildcardPattern":
      // No bindings
      break;
  }
}

// Bind a pattern to a type, with optional mutability
export function bindPattern(ctx: InferContext, pattern: AST.Pattern, type: Type, mutable: boolean = false): void {
  switch (pattern.kind) {
    case "IdentifierPattern":
      try {
        ctx.env.define(pattern.name, type, mutable);
      } catch (e) {
        const err = TypeErrors.variableAlreadyDefined(pattern.name);
        error(ctx, err.message, pattern.loc, err.hint);
      }
      break;
    case "ObjectPattern":
      if (type.kind === "object") {
        for (const prop of pattern.properties) {
          const propType = type.properties.find(p => p.name === prop.key);
          bindPattern(ctx, prop.pattern, propType?.type ?? Types.any, mutable);
        }
      } else {
        for (const prop of pattern.properties) {
          bindPattern(ctx, prop.pattern, Types.any, mutable);
        }
      }
      break;
    case "ArrayPattern":
      const elementType = type.kind === "list" ? type.elementType : Types.any;
      for (const el of pattern.elements) {
        bindPattern(ctx, el, elementType, mutable);
      }
      break;
    case "RestPattern":
      ctx.env.define(pattern.name, type.kind === "list" ? type : Types.list(Types.any), mutable);
      break;
  }
}
