// Expression Type Inference - Infers types for all expression kinds
import * as AST from "../../../parser/ast";
import type { Type, FunctionType, ObjectType, ParameterType } from "../../types";
import { Types, typeToString, isNullable, nonNull } from "../../types";
import { TypeErrors } from "../../../shared/errors";
import {
  astTypeToType, resolveTypeName, isAssignable,
  findCommonType, typeInvolvesPromise, substituteTypeParams, unifyTypes,
  substituteTypeInObject
} from "../../type-utils";
import { constructGenericType } from "../../primitives";
import type { InferContext } from "./context";
import { error, warning, recordType } from "./context";
import { checkPattern } from "./check-pattern";

// Forward declaration for checkBlock (will be provided by check-stmt)
export let checkBlockFn: (ctx: InferContext, block: AST.Block) => void;
export function setCheckBlockFn(fn: (ctx: InferContext, block: AST.Block) => void) {
  checkBlockFn = fn;
}

export function inferExpr(ctx: InferContext, expr: AST.Expr): Type {
  let type: Type;

  switch (expr.kind) {
    case "Literal":
      type = inferLiteral(expr);
      break;
    case "Identifier":
      type = inferIdentifier(ctx, expr);
      break;
    case "BinaryExpr":
      type = inferBinaryExpr(ctx, expr);
      break;
    case "UnaryExpr":
      type = inferUnaryExpr(ctx, expr);
      break;
    case "CallExpr":
      type = inferCallExpr(ctx, expr);
      break;
    case "IndexExpr":
      type = inferIndexExpr(ctx, expr);
      break;
    case "MemberExpr":
      type = inferMemberExpr(ctx, expr);
      break;
    case "PipeExpr":
      type = inferPipeExpr(ctx, expr);
      break;
    case "LambdaExpr":
      type = inferLambdaExpr(ctx, expr);
      break;
    case "IfExpr":
      type = inferIfExpr(ctx, expr);
      break;
    case "MatchExpr":
      type = inferMatchExpr(ctx, expr);
      break;
    case "ListExpr":
      type = inferListExpr(ctx, expr);
      break;
    case "MapExpr":
      type = inferMapExpr(ctx, expr);
      break;
    case "SpawnExpr":
      type = inferSpawnExpr(ctx, expr);
      break;
    case "TypeAssertion": {
      const exprType = inferExpr(ctx, expr.expr);
      const assertedType = astTypeToType(expr.type);
      // Allow assertion if types are related (one is subtype of other, or both same kind)
      const canAssert = 
        exprType.kind === "any" || assertedType.kind === "any" ||
        isAssignable(exprType, assertedType, ctx.env) ||
        isAssignable(assertedType, exprType, ctx.env);
      if (!canAssert) {
        const err = TypeErrors.invalidTypeAssertion(typeToString(exprType), typeToString(assertedType));
        error(ctx, err.message, expr.loc, err.hint);
      }
      type = assertedType;
      break;
    }
    case "NullAssertion": {
      const innerType = inferExpr(ctx, expr.expr);
      if (!isNullable(innerType)) {
        const err = TypeErrors.unnecessaryNullAssertion(typeToString(innerType));
        warning(ctx, `${err.message}. ${err.hint}`);
      }
      type = nonNull(innerType);
      break;
    }
    case "RangeExpr":
      type = Types.list(Types.number);
      break;
    case "TemplateLiteral":
      type = inferTemplateLiteral(ctx, expr);
      break;
    default:
      type = Types.any;
  }

  recordType(ctx, expr, type);
  return type;
}

function inferLiteral(expr: AST.Literal): Type {
  if (typeof expr.value === "number") return Types.number;
  if (typeof expr.value === "string") return Types.string;
  if (typeof expr.value === "boolean") return Types.bool;
  if (expr.value === null) return Types.null;
  return Types.any;
}

function inferIdentifier(ctx: InferContext, expr: AST.Identifier): Type {
  const symbol = ctx.env.lookup(expr.name);
  if (!symbol) {
    const typeRef = ctx.env.lookupType(expr.name);
    if (typeRef) {
      if (typeRef.kind === "object" && typeRef.name) {
        const obj = typeRef as ObjectType;
        // Factory params in declaration order: embedded first, then own fields
        // Exclude promoted props
        const ownProps = obj.properties.filter(p => !p.promotedFrom);
        const params: ParameterType[] = [];
        for (const p of ownProps) {
          if (p.embedded) {
            const embeddedType = ctx.env.lookupType(p.name);
            params.push(Types.param(p.name, embeddedType || Types.any, true));
          } else {
            params.push(Types.param(p.name, p.type, p.optional || !!p.defaultValue));
          }
        }
        return Types.fn(params, typeRef);
      }
      return typeRef;
    }
    const err = TypeErrors.unknownIdentifier(expr.name);
    error(ctx, err.message, expr.loc, err.hint);
    return Types.any;
  }
  return symbol.type;
}

function inferBinaryExpr(ctx: InferContext, expr: AST.BinaryExpr): Type {
  const leftType = inferExpr(ctx, expr.left);
  const rightType = inferExpr(ctx, expr.right);

  switch (expr.op) {
    case "+":
      if (leftType.kind === "string" || rightType.kind === "string") {
        return Types.string;
      }
      if (leftType.kind !== "number" && leftType.kind !== "any") {
        const err = TypeErrors.operatorRequiresType("+", "number or string", typeToString(leftType));
        error(ctx, err.message, expr.left.loc, err.hint);
      }
      if (rightType.kind !== "number" && rightType.kind !== "any") {
        const err = TypeErrors.operatorRequiresType("+", "number or string", typeToString(rightType));
        error(ctx, err.message, expr.right.loc, err.hint);
      }
      return Types.number;
    case "-":
    case "*":
    case "/":
    case "%":
    case "^":
      if (leftType.kind !== "number" && leftType.kind !== "any") {
        const err = TypeErrors.operatorRequiresType(expr.op, "number", typeToString(leftType));
        error(ctx, err.message, expr.left.loc, err.hint);
      }
      if (rightType.kind !== "number" && rightType.kind !== "any") {
        const err = TypeErrors.operatorRequiresType(expr.op, "number", typeToString(rightType));
        error(ctx, err.message, expr.right.loc, err.hint);
      }
      return Types.number;
    case "<":
    case ">":
    case "<=":
    case ">=": {
      const leftBase = leftType.kind === "optional" ? leftType.inner : leftType;
      const rightBase = rightType.kind === "optional" ? rightType.inner : rightType;
      if (leftBase.kind !== "any" && rightBase.kind !== "any" &&
          leftBase.kind !== rightBase.kind &&
          !((leftBase.kind === "number" || leftBase.kind === "string") &&
            (rightBase.kind === "number" || rightBase.kind === "string"))) {
        const err = TypeErrors.cannotCompare(typeToString(leftType), typeToString(rightType));
        error(ctx, err.message, expr.loc, err.hint);
      }
      return Types.bool;
    }
    case "==":
    case "!=":
    case "and":
    case "or":
    case "is":
      return Types.bool;
    case "??":
      if (isNullable(leftType)) {
        return Types.union(nonNull(leftType), rightType);
      }
      return leftType;
    default:
      return Types.any;
  }
}

function inferUnaryExpr(ctx: InferContext, expr: AST.UnaryExpr): Type {
  const operandType = inferExpr(ctx, expr.operand);

  switch (expr.op) {
    case "-":
      if (operandType.kind !== "number" && operandType.kind !== "any") {
        const err = TypeErrors.operatorRequiresType("-", "number", typeToString(operandType));
        error(ctx, err.message, expr.operand.loc, err.hint);
      }
      return Types.number;
    case "not":
    case "!":
      return Types.bool;
    default:
      return operandType;
  }
}

function inferCallExpr(ctx: InferContext, expr: AST.CallExpr): Type {
  // Handle generic constructor calls like TypeName[T](...)
  if (expr.callee.kind === "IndexExpr" && expr.callee.object.kind === "Identifier") {
    const constructorName = expr.callee.object.name;
    
    // Collect type arguments
    const allTypeArgs: AST.Expr[] = [expr.callee.index];
    if (expr.callee.typeArgs) {
      allTypeArgs.push(...expr.callee.typeArgs);
    }
    
    // Resolve type arguments to Types
    const resolvedTypeArgs = allTypeArgs.map(arg => 
      resolveTypeName(arg.kind === "Identifier" ? arg.name : "any", ctx.env)
    );
    
    // Check if this is a built-in generic type (Channel, etc.)
    const builtinType = constructGenericType(constructorName, resolvedTypeArgs);
    if (builtinType) {
      // Validate constructor arguments against the extern type definition
      const baseType = ctx.env.lookupType(constructorName);
      if (baseType && baseType.kind === "object") {
        const typeParams = baseType.typeParams || [];
        const bindings = new Map<string, Type>();
        for (let i = 0; i < typeParams.length && i < resolvedTypeArgs.length; i++) {
          bindings.set(typeParams[i]!.name, resolvedTypeArgs[i]!);
        }
        const instantiated = substituteTypeInObject(baseType, bindings);
        // Check constructor arguments
        inferConstructorCall(ctx, expr, instantiated);
      }
      return builtinType;
    }
    
    // Generic type constructor calls for user-defined types like Channel[number](...) or Pair[A, B](...)
    const baseType = ctx.env.lookupType(constructorName);
    if (baseType && baseType.kind === "object") {
      // Substitute type parameters in the base type
      const typeParams = baseType.typeParams || [];
      const bindings = new Map<string, Type>();
      for (let i = 0; i < typeParams.length && i < resolvedTypeArgs.length; i++) {
        bindings.set(typeParams[i]!.name, resolvedTypeArgs[i]!);
      }
      const instantiated = substituteTypeInObject(baseType, bindings);
      // Validate constructor arguments
      inferConstructorCall(ctx, expr, instantiated);
      // Return a generic type that preserves the type arguments for assignability
      if (typeParams.length > 0 && resolvedTypeArgs.length > 0) {
        return Types.generic(Types.ref(constructorName), resolvedTypeArgs);
      }
      return instantiated;
    }
  }

  const calleeType = inferExpr(ctx, expr.callee);

  // Consume spawns for race/all
  if (expr.callee.kind === "Identifier" &&
      (expr.callee.name === "race" || expr.callee.name === "all")) {
    markSpawnsConsumed(ctx, expr.args);
  } else if (calleeType.kind === "function") {
    const params = calleeType.params;
    for (let i = 0; i < expr.args.length && i < params.length; i++) {
      const param = params[i];
      if (param && typeInvolvesPromise(param.type, ctx.env)) {
        const arg = expr.args[i];
        const argExpr = arg && "kind" in arg ? arg : arg?.value;
        if (argExpr) consumeSpawnsInExpr(ctx, argExpr);
      }
    }
  }

  if (calleeType.kind === "function") {
    return inferFunctionCall(ctx, expr, calleeType);
  }

  if (calleeType.kind === "object") {
    return inferConstructorCall(ctx, expr, calleeType);
  }

  // Infer arguments for unknown callees
  for (const arg of expr.args) {
    if ("name" in arg && "value" in arg) {
      inferExpr(ctx, arg.value);
    } else {
      inferExpr(ctx, arg as AST.Expr);
    }
  }

  return Types.any;
}

function inferFunctionCall(ctx: InferContext, expr: AST.CallExpr, fnType: FunctionType): Type {
  const args = expr.args;
  const hasNamed = args.some((a) => "name" in a && "value" in a);
  const hasPositional = args.some((a) => !("name" in a && "value" in a));
  if (hasNamed && hasPositional) {
    const err = TypeErrors.mixedPositionalAndNamedArguments();
    error(ctx, err.message, expr.loc, err.hint);
  }

  // Infer type parameters
  const typeBindings = inferTypeParams(ctx, fnType, args);

  // Substitute type params in parameter types
  const params = fnType.params.map(p => ({
    ...p,
    type: substituteTypeParams(p.type, typeBindings)
  }));

  const requiredCount = params.filter(p => !p.optional && !p.rest).length;
  const hasRest = params.some(p => p.rest);
  const maxArgs = hasRest ? Infinity : params.length;

  if (args.length < requiredCount) {
    const err = TypeErrors.wrongArgumentCount(`at least ${requiredCount}`, args.length);
    error(ctx, err.message, expr.loc, err.hint);
  } else if (args.length > maxArgs) {
    const err = TypeErrors.wrongArgumentCount(`at most ${params.length}`, args.length);
    error(ctx, err.message, expr.loc, err.hint);
  }

  for (let i = 0; i < args.length; i++) {
    const arg = args[i]!;
    let argType: Type;
    let argLoc: AST.SourceLocation;

    if ("name" in arg && "value" in arg) {
      argType = inferExpr(ctx, arg.value);
      argLoc = arg.value.loc;
      const param = params.find(p => p.name === arg.name);
      if (!param) {
        const err = TypeErrors.unknownParameter(arg.name, params.map(p => p.name).filter(Boolean) as string[]);
        error(ctx, err.message, arg.value.loc, err.hint);
      } else if (!isAssignable(argType, param.type, ctx.env)) {
        const err = TypeErrors.typeMismatch(typeToString(param.type), typeToString(argType));
        error(ctx, `Argument '${arg.name}': ${err.message}`, arg.value.loc, err.hint);
      }
    } else {
      argType = inferExpr(ctx, arg as AST.Expr);
      argLoc = (arg as AST.Expr).loc;
      const paramIndex = Math.min(i, params.length - 1);
      const param = params[paramIndex];
      if (param) {
        const expectedType = param.rest && param.type.kind === "list" ?
          param.type.elementType : param.type;
        if (!isAssignable(argType, expectedType, ctx.env)) {
          const err = TypeErrors.typeMismatch(typeToString(expectedType), typeToString(argType));
          error(ctx, `Argument ${i + 1}: ${err.message}`, argLoc, err.hint);
        }
      }
    }
  }

  // Check if required context types are available
  // Note: This is a heuristic check - full context type checking would require tracking
  // available context types, not just variable names. Keep as warning for now.
  for (const binding of fnType.context) {
    if (binding.name && !ctx.env.isDefined(binding.name) && !ctx.insideWithContext) {
      warning(ctx, `Function requires '${binding.name}' in context which may not be available`);
    }
  }

  const returnType = substituteTypeParams(fnType.returnType, typeBindings);

  if (returnType.kind === "object" &&
      (returnType as ObjectType).isContextType &&
      !ctx.insideWithContext) {
    error(ctx, `Context type '${returnType.name}' can only be instantiated in 'with' clauses`, expr.loc);
  }

  return returnType;
}

function inferConstructorCall(ctx: InferContext, expr: AST.CallExpr, objType: any): Type {
  if (objType.isContextType && !ctx.insideWithContext) {
    error(ctx, `Context type '${objType.name}' can only be instantiated in 'with' clauses`, expr.loc);
  }

  const args = expr.args;
  const hasNamed = args.some((a) => "name" in a && "value" in a);
  const hasPositional = args.some((a) => !("name" in a && "value" in a));
  if (hasNamed && hasPositional) {
    const err = TypeErrors.mixedPositionalAndNamedArguments();
    error(ctx, err.message, expr.loc, err.hint);
  }

  // Props in declaration order, excluding promoted and Context (marker type)
  const ownProps = objType.properties.filter((p: any) => !p.promotedFrom && !(p.embedded && p.name === "Context"));
  
  // Count required: non-embedded without optional/default
  const requiredCount = ownProps.filter((p: any) => !p.embedded && !p.optional && !p.defaultValue).length;
  const maxArgs = ownProps.length;

  if (args.length < requiredCount) {
    const err = TypeErrors.wrongArgumentCount(`at least ${requiredCount}`, args.length);
    error(ctx, `Type '${objType.name}': ${err.message}`, expr.loc, err.hint);
  } else if (args.length > maxArgs) {
    const err = TypeErrors.wrongArgumentCount(`at most ${maxArgs}`, args.length);
    error(ctx, `Type '${objType.name}': ${err.message}`, expr.loc, err.hint);
  }

  for (let i = 0; i < args.length; i++) {
    const arg = args[i]!;
    let argType: Type;

    if ("name" in arg && "value" in arg) {
      argType = inferExpr(ctx, arg.value);
      const prop = ownProps.find((p: any) => p.name === arg.name);
      if (!prop) {
        const err = TypeErrors.propertyNotExist(arg.name, objType.name!);
        error(ctx, err.message, arg.value.loc, err.hint);
      } else {
        const expectedType = prop.embedded ? ctx.env.lookupType(prop.name) || Types.any : prop.type;
        if (!isAssignable(argType, expectedType, ctx.env)) {
          const err = TypeErrors.typeMismatch(typeToString(expectedType), typeToString(argType));
          error(ctx, `Property '${arg.name}': ${err.message}`, arg.value.loc, err.hint);
        }
      }
    } else {
      argType = inferExpr(ctx, arg as AST.Expr);
      const prop = ownProps[i];
      if (prop) {
        const expectedType = prop.embedded ? ctx.env.lookupType(prop.name) || Types.any : prop.type;
        if (!isAssignable(argType, expectedType, ctx.env)) {
          const err = TypeErrors.typeMismatch(typeToString(expectedType), typeToString(argType));
          error(ctx, `Argument ${i + 1}: ${err.message}`, (arg as AST.Expr).loc, err.hint);
        }
      }
    }
  }

  return objType;
}

function inferIndexExpr(ctx: InferContext, expr: AST.IndexExpr): Type {
  const objectType = inferExpr(ctx, expr.object);

  if (expr.slice) {
    if (expr.slice.start) {
      const startType = inferExpr(ctx, expr.slice.start);
      if (startType.kind !== "number" && startType.kind !== "any") {
        const err = TypeErrors.indexTypeMismatch("number", typeToString(startType));
        error(ctx, `Slice start index: ${err.message}`, expr.slice.start.loc, err.hint);
      }
    }
    if (expr.slice.end) {
      const endType = inferExpr(ctx, expr.slice.end);
      if (endType.kind !== "number" && endType.kind !== "any") {
        const err = TypeErrors.indexTypeMismatch("number", typeToString(endType));
        error(ctx, `Slice end index: ${err.message}`, expr.slice.end.loc, err.hint);
      }
    }
    return objectType;
  }

  const indexType = inferExpr(ctx, expr.index);

  if (objectType.kind === "list") {
    if (indexType.kind !== "number" && indexType.kind !== "any") {
      const err = TypeErrors.indexTypeMismatch("number", typeToString(indexType));
      error(ctx, `List index: ${err.message}`, expr.index.loc, err.hint);
    }
    return objectType.elementType;
  }
  if (objectType.kind === "map") {
    if (!isAssignable(indexType, objectType.keyType, ctx.env)) {
      const err = TypeErrors.indexTypeMismatch(typeToString(objectType.keyType), typeToString(indexType));
      error(ctx, `Map key: ${err.message}`, expr.index.loc, err.hint);
    }
    return Types.optional(objectType.valueType);
  }
  if (objectType.kind === "string") {
    if (indexType.kind !== "number" && indexType.kind !== "any") {
      const err = TypeErrors.indexTypeMismatch("number", typeToString(indexType));
      error(ctx, `String index: ${err.message}`, expr.index.loc, err.hint);
    }
    return Types.string;
  }

  return Types.any;
}

function inferMemberExpr(ctx: InferContext, expr: AST.MemberExpr): Type {
  const objectType = inferExpr(ctx, expr.object);
  let resolved = ctx.env.resolveType(objectType);

  // Handle generic types like Container[string] - resolve and substitute
  if (resolved.kind === "generic" && resolved.base.kind === "ref") {
    const baseType = ctx.env.lookupType(resolved.base.name);
    if (baseType && baseType.kind === "object") {
      const typeParams = baseType.typeParams || [];
      const bindings = new Map<string, Type>();
      for (let i = 0; i < typeParams.length && i < resolved.args.length; i++) {
        bindings.set(typeParams[i]!.name, resolved.args[i]!);
      }
      resolved = substituteTypeInObject(baseType, bindings);
    }
  }

  if (resolved.kind === "object") {
    const prop = resolved.properties.find(p => p.name === expr.property);
    if (prop) {
      // Check private member access (members starting with _)
      if (expr.property.startsWith("_") && resolved.name && ctx.currentTypeName !== resolved.name) {
        const err = TypeErrors.privateAccess(expr.property, resolved.name);
        error(ctx, err.message, expr.loc, err.hint);
      }
      return expr.optional ? Types.optional(prop.type) : prop.type;
    }
    const method = resolved.methods.find(m => m.name === expr.property);
    if (method) {
      // Check private method access (methods starting with _)
      if (expr.property.startsWith("_") && resolved.name && ctx.currentTypeName !== resolved.name) {
        const err = TypeErrors.privateAccess(expr.property, resolved.name);
        error(ctx, err.message, expr.loc, err.hint);
      }
      return method.type;
    }
    if (resolved.name && !expr.optional) {
      const err = TypeErrors.propertyNotExist(expr.property, resolved.name);
      error(ctx, err.message, expr.loc, err.hint);
    }
  }

  // Built-in properties and methods
  return inferBuiltinMember(ctx, objectType, expr);
}

function inferBuiltinMember(ctx: InferContext, objectType: Type, expr: AST.MemberExpr): Type {
  // Look up method/property from builtin registry
  const member = ctx.env.lookupBuiltinMethod(objectType.kind, expr.property);
  
  if (member) {
    let memberType = member.type;
    
    // Substitute type parameters based on the object type
    if (member.isProperty) {
      memberType = substituteBuiltinTypeParams(memberType, objectType);
    } else {
      memberType = substituteBuiltinTypeParams(memberType, objectType);
    }
    
    return memberType;
  }
  
  // Special case: Maps allow arbitrary key access via dot notation
  if (objectType.kind === "map") {
    return expr.optional ? Types.optional(objectType.valueType) : objectType.valueType;
  }

  // Handle types without properties
  if (objectType.kind === "number" || objectType.kind === "bool") {
    if (!expr.optional) {
      error(ctx, `Property '${expr.property}' does not exist on type '${objectType.kind}'`, expr.loc);
    }
    return expr.optional ? Types.optional(Types.any) : Types.any;
  }

  // For builtin primitive types that should have properties defined
  if (objectType.kind === "string" || objectType.kind === "list" || objectType.kind === "set") {
    if (!expr.optional) {
      error(ctx, `Property '${expr.property}' does not exist on type '${objectType.kind}'`, expr.loc);
    }
    return expr.optional ? Types.optional(Types.any) : Types.any;
  }

  // For any/unknown types, allow any property access
  return expr.optional ? Types.optional(Types.any) : Types.any;
}

// Substitute type parameters (T, K, V) in method types based on the actual object type
// Only for true primitives - Channel is handled as a regular ObjectType
function substituteBuiltinTypeParams(type: Type, objectType: Type): Type {
  const bindings = new Map<string, Type>();
  
  // Build bindings based on object type kind (primitives only)
  if (objectType.kind === "list") {
    bindings.set("T", objectType.elementType);
  } else if (objectType.kind === "map") {
    bindings.set("K", objectType.keyType);
    bindings.set("V", objectType.valueType);
  } else if (objectType.kind === "set") {
    bindings.set("T", objectType.elementType);
  }
  
  if (bindings.size === 0) {
    return type;
  }
  
  return substituteTypeParams(type, bindings);
}

function inferPipeExpr(ctx: InferContext, expr: AST.PipeExpr): Type {
  const leftType = inferExpr(ctx, expr.left);
  
  // If right side is a call expression, the left side becomes the first argument
  if (expr.right.kind === "CallExpr") {
    const callExpr = expr.right;
    const calleeType = inferExpr(ctx, callExpr.callee);
    
    if (calleeType.kind === "function") {
      // Create a synthetic call with left prepended to args
      const syntheticArgs: (AST.Expr | { name: string; value: AST.Expr })[] = [
        expr.left,
        ...callExpr.args
      ];
      
      // Infer type parameters with the synthetic args
      const typeBindings = inferTypeParams(ctx, calleeType, syntheticArgs);
      
      // Substitute type params in parameter types
      const params = calleeType.params.map(p => ({
        ...p,
        type: substituteTypeParams(p.type, typeBindings)
      }));
      
      // Check argument count (left + explicit args)
      const requiredCount = params.filter(p => !p.optional && !p.rest).length;
      const totalArgs = 1 + callExpr.args.length;
      
      if (totalArgs < requiredCount) {
        const err = TypeErrors.wrongArgumentCount(`at least ${requiredCount}`, totalArgs);
        error(ctx, err.message, callExpr.loc, err.hint);
      }
      
      // Check left against first param
      if (params.length > 0) {
        const firstParam = params[0]!;
        if (!isAssignable(leftType, firstParam.type, ctx.env)) {
          const err = TypeErrors.typeMismatch(typeToString(firstParam.type), typeToString(leftType));
          error(ctx, `Pipe argument: ${err.message}`, expr.left.loc, err.hint);
        }
      }
      
      // Check remaining args against remaining params
      for (let i = 0; i < callExpr.args.length; i++) {
        const arg = callExpr.args[i]!;
        const paramIndex = i + 1; // +1 because left is first arg
        const param = paramIndex < params.length ? params[paramIndex] : params[params.length - 1];
        
        if (param) {
          let argType: Type;
          let argLoc: AST.SourceLocation;
          
          if ("name" in arg && "value" in arg) {
            argType = inferExpr(ctx, arg.value);
            argLoc = arg.value.loc;
          } else {
            argType = inferExpr(ctx, arg as AST.Expr);
            argLoc = (arg as AST.Expr).loc;
          }
          
          const expectedType = param.rest && param.type.kind === "list" ?
            param.type.elementType : param.type;
          if (!isAssignable(argType, expectedType, ctx.env)) {
            const err = TypeErrors.typeMismatch(typeToString(expectedType), typeToString(argType));
            error(ctx, `Argument ${paramIndex + 1}: ${err.message}`, argLoc, err.hint);
          }
        }
      }
      
      return substituteTypeParams(calleeType.returnType, typeBindings);
    }
    
    // Infer args anyway for non-function callees
    for (const arg of callExpr.args) {
      if ("name" in arg && "value" in arg) {
        inferExpr(ctx, arg.value);
      } else {
        inferExpr(ctx, arg as AST.Expr);
      }
    }
    return Types.any;
  }
  
  // For simple identifier or other expression on the right
  const rightType = inferExpr(ctx, expr.right);
  if (rightType.kind === "function") {
    return rightType.returnType;
  }
  return Types.any;
}

function inferLambdaExpr(ctx: InferContext, expr: AST.LambdaExpr): Type {
  const params = expr.params.map(p => ({
    name: p.name,
    type: p.type ? astTypeToType(p.type) : Types.any,
    optional: p.optional,
    rest: p.rest,
  }));

  const lambdaEnv = ctx.env.child();
  for (const param of params) {
    lambdaEnv.define(param.name, param.type);
  }

  const savedEnv = ctx.env;
  ctx.env = lambdaEnv;

  let returnType: Type;
  if (expr.body.kind === "Block") {
    checkBlockFn(ctx, expr.body as AST.Block);
    returnType = Types.void;
  } else {
    returnType = inferExpr(ctx, expr.body as AST.Expr);
  }

  ctx.env = savedEnv;
  return Types.fn(params, returnType);
}

function inferIfExpr(ctx: InferContext, expr: AST.IfExpr): Type {
  inferExpr(ctx, expr.condition);
  const thenType = inferExpr(ctx, expr.then);
  const elseType = inferExpr(ctx, expr.else);

  if (isAssignable(thenType, elseType, ctx.env)) {
    return elseType;
  }
  if (isAssignable(elseType, thenType, ctx.env)) {
    return thenType;
  }
  return Types.union(thenType, elseType);
}

function inferMatchExpr(ctx: InferContext, expr: AST.MatchExpr): Type {
  const valueType = inferExpr(ctx, expr.value);
  const armTypes: Type[] = [];

  for (const arm of expr.arms) {
    const armEnv = ctx.env.child();
    const savedEnv = ctx.env;
    ctx.env = armEnv;

    checkPattern(ctx, arm.pattern, valueType);
    if (arm.guard) {
      inferExpr(ctx, arm.guard);
    }

    let armType: Type;
    if (arm.body.kind === "Block") {
      checkBlockFn(ctx, arm.body as AST.Block);
      armType = Types.void;
    } else {
      armType = inferExpr(ctx, arm.body as AST.Expr);
    }
    armTypes.push(armType);

    ctx.env = savedEnv;
  }

  if (armTypes.length === 0) return Types.never;
  if (armTypes.length === 1) return armTypes[0]!;
  return Types.union(...armTypes);
}

function inferListExpr(ctx: InferContext, expr: AST.ListExpr): Type {
  if (expr.elements.length === 0) {
    return Types.list(Types.any);
  }

  const elementTypes: Type[] = [];
  for (const el of expr.elements) {
    if (el.kind === "SpreadElement") {
      const spreadType = inferExpr(ctx, el.expr);
      if (spreadType.kind === "list") {
        elementTypes.push(spreadType.elementType);
      }
      if (el.expr.kind === "Identifier") {
        ctx.unawaitedSpawns.delete(el.expr.name);
      }
    } else {
      elementTypes.push(inferExpr(ctx, el));
      if (el.kind === "Identifier") {
        ctx.unawaitedSpawns.delete(el.name);
      }
    }
  }

  const commonType = findCommonType(elementTypes);
  return Types.list(commonType);
}

function inferMapExpr(ctx: InferContext, expr: AST.MapExpr): Type {
  if (expr.entries.length === 0) {
    return Types.map(Types.string, Types.any);
  }

  const keyTypes: Type[] = [];
  const valueTypes: Type[] = [];

  for (const entry of expr.entries) {
    if (!entry.spread) {
      if (entry.key.kind === "Identifier") {
        keyTypes.push(Types.string);
      } else {
        keyTypes.push(inferExpr(ctx, entry.key));
      }
      valueTypes.push(inferExpr(ctx, entry.value));
    }
  }

  const keyType = findCommonType(keyTypes);
  const valueType = findCommonType(valueTypes);
  return Types.map(keyType, valueType);
}

function inferSpawnExpr(ctx: InferContext, expr: AST.SpawnExpr): Type {
  if (ctx.functionWithDepth > 0) {
    error(ctx,
      `Cannot use 'spawn' inside function-level 'with' block - spawned task may outlive context scope`,
      expr.loc,
      `Move spawn outside the 'with' block or use top-level 'with' instead`
    );
  }

  const innerType = inferExpr(ctx, expr.expr);
  return Types.promise(innerType.kind === "function" ? (innerType as FunctionType).returnType : innerType);
}

function inferTemplateLiteral(ctx: InferContext, expr: AST.TemplateLiteral): Type {
  for (const part of expr.parts) {
    if (typeof part !== "string") {
      inferExpr(ctx, part.expr);
    }
  }
  return Types.string;
}

// Spawn tracking helpers
function markSpawnsConsumed(ctx: InferContext, args: (AST.Expr | { name: string; value: AST.Expr })[]): void {
  for (const arg of args) {
    const expr = "kind" in arg ? arg : arg.value;
    consumeSpawnsInExpr(ctx, expr);
  }
}

export function consumeSpawnsInExpr(ctx: InferContext, expr: AST.Expr): void {
  switch (expr.kind) {
    case "Identifier":
      ctx.unawaitedSpawns.delete(expr.name);
      break;
    case "ListExpr":
      for (const el of expr.elements) {
        if (el.kind !== "SpreadElement") {
          consumeSpawnsInExpr(ctx, el);
        } else {
          consumeSpawnsInExpr(ctx, el.expr);
        }
      }
      break;
    case "MapExpr":
      for (const entry of expr.entries) {
        consumeSpawnsInExpr(ctx, entry.value);
      }
      break;
    case "IfExpr":
      consumeSpawnsInExpr(ctx, expr.then);
      if (expr.else) consumeSpawnsInExpr(ctx, expr.else);
      break;
    case "IndexExpr":
      consumeSpawnsInExpr(ctx, expr.object);
      break;
    case "MemberExpr":
      consumeSpawnsInExpr(ctx, expr.object);
      break;
    case "CallExpr": {
      const callReturnType = ctx.types.get(expr) ?? Types.any;
      const isValuesCall = expr.callee.kind === "Identifier" && expr.callee.name === "values";
      if (typeInvolvesPromise(callReturnType, ctx.env) || isValuesCall) {
        for (const arg of expr.args) {
          const argExpr = "kind" in arg ? arg : arg.value;
          consumeSpawnsInExpr(ctx, argExpr);
        }
      }
      break;
    }
  }
}

export function exprContainsSpawn(ctx: InferContext, expr: AST.Expr): boolean {
  if (expr.kind === "SpawnExpr") return true;
  if (expr.kind === "Identifier" && ctx.unawaitedSpawns.has(expr.name)) return true;

  if (expr.kind === "CallExpr") {
    for (const arg of expr.args) {
      const argExpr = "kind" in arg ? arg : arg.value;
      if (exprContainsSpawn(ctx, argExpr)) return true;
    }
  }

  if (expr.kind === "ListExpr") {
    for (const el of expr.elements) {
      if (el.kind === "SpreadElement") {
        if (exprContainsSpawn(ctx, el.expr)) return true;
      } else if (exprContainsSpawn(ctx, el)) {
        return true;
      }
    }
  }

  if (expr.kind === "MapExpr") {
    for (const entry of expr.entries) {
      if (exprContainsSpawn(ctx, entry.value)) return true;
    }
  }

  if (expr.kind === "IndexExpr" && expr.object.kind === "Identifier") {
    if (ctx.unawaitedSpawns.has(expr.object.name)) return true;
  }
  if (expr.kind === "MemberExpr" && expr.object.kind === "Identifier") {
    if (ctx.unawaitedSpawns.has(expr.object.name)) return true;
  }

  if (expr.kind === "IfExpr") {
    if (exprContainsSpawn(ctx, expr.then)) return true;
    if (expr.else && exprContainsSpawn(ctx, expr.else)) return true;
  }

  return false;
}

export function transferSpawnTracking(ctx: InferContext, expr: AST.Expr): void {
  if (expr.kind === "Identifier") {
    ctx.unawaitedSpawns.delete(expr.name);
  } else if (expr.kind === "IfExpr") {
    if (expr.then.kind === "Identifier") ctx.unawaitedSpawns.delete(expr.then.name);
    if (expr.else?.kind === "Identifier") ctx.unawaitedSpawns.delete(expr.else.name);
  } else if (expr.kind === "ListExpr") {
    for (const el of expr.elements) {
      if (el.kind === "Identifier") ctx.unawaitedSpawns.delete(el.name);
      else if (el.kind === "SpreadElement" && el.expr.kind === "Identifier") {
        ctx.unawaitedSpawns.delete(el.expr.name);
      }
    }
  } else if (expr.kind === "MapExpr") {
    for (const entry of expr.entries) {
      if (entry.value.kind === "Identifier") ctx.unawaitedSpawns.delete(entry.value.name);
    }
  } else if (expr.kind === "CallExpr") {
    for (const arg of expr.args) {
      const argExpr = "kind" in arg ? arg : arg.value;
      transferSpawnTracking(ctx, argExpr);
    }
  }
}

// Type parameter inference
function inferTypeParams(ctx: InferContext, fnType: FunctionType, args: (AST.Expr | NamedArg)[]): Map<string, Type> {
  const bindings = new Map<string, Type>();
  if (!fnType.typeParams) return bindings;

  for (const tp of fnType.typeParams) {
    bindings.set(tp.name, Types.any);
  }

  for (let i = 0; i < args.length && i < fnType.params.length; i++) {
    const arg = args[i]!;
    const argExpr = "kind" in arg ? arg : arg.value;
    const argType = inferExpr(ctx, argExpr);
    const paramType = fnType.params[i]!.type;
    unifyTypes(paramType, argType, bindings);
  }

  return bindings;
}

// Named argument type (not exported from AST module)
type NamedArg = { name: string; value: AST.Expr };
