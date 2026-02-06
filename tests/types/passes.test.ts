import { describe, test, expect } from "bun:test";
import { Parser } from "../../src/parser/parser";
import {
  PassManager,
  CollectDeclarationsPass,
  InferTypesPass,
  ContextAnalysisPass,
  type Pass,
  type PassContext,
} from "../../src/types/pass-manager";
import { createGlobalEnvironment, TypeEnvironment } from "../../src/types/environment";
import { collectDeclarations } from "../../src/types/passes/collect-declarations";
import { inferTypes } from "../../src/types/passes/infer-types";
import { analyzeContext } from "../../src/types/passes/context-analysis";
import { typeToString } from "../../src/types";
import * as TypeUtils from "../../src/types/type-utils";
import { Types } from "../../src/types/types";

// Helper to parse source
const parse = (src: string) => new Parser(src).parse();

// Helper to check via PassManager
const checkWithPassManager = (src: string) => {
  const program = parse(src);
  const manager = PassManager.createDefault();
  return manager.run(program);
};

describe("PassManager - Full Pipeline", () => {
  test("basic program passes all checks", () => {
    const result = checkWithPassManager(`let x = 1
x + 2`);
    expect(result.errors).toHaveLength(0);
  });

  test("type error detected", () => {
    const result = checkWithPassManager(`let x: string = 42`);
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0]!.message).toContain("not assignable");
  });

  test("unknown identifier error", () => {
    const result = checkWithPassManager(`y + 1`);
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0]!.message).toContain("Unknown identifier");
  });

  test("collects types for expressions", () => {
    const result = checkWithPassManager(`let x = 42`);
    // Types are now stored on AST nodes via resolvedType
    const letStmt = result.program.body[0];
    expect(letStmt?.kind).toBe("LetStmt");
    if (letStmt?.kind === "LetStmt") {
      expect(letStmt.value.resolvedType).toBeDefined();
    }
  });
});

describe("Pass 1: Collect Declarations", () => {
  test("collects function declarations", () => {
    const program = parse(`fn add(a: number, b: number): number
  a + b`);
    const env = createGlobalEnvironment();
    const result = collectDeclarations({ program, env });
    
    expect(result.fnDecls.has("add")).toBe(true);
    expect(result.errors).toHaveLength(0);
  });

  test("collects type declarations", () => {
    const program = parse(`type Point
  x: number
  y: number`);
    const env = createGlobalEnvironment();
    const result = collectDeclarations({ program, env });
    
    const pointType = result.env.lookupType("Point");
    expect(pointType).toBeDefined();
    expect(pointType?.kind).toBe("object");
  });

  test("detects duplicate function", () => {
    const program = parse(`fn foo(): number
  1
fn foo(): string
  "hi"`);
    const env = createGlobalEnvironment();
    const result = collectDeclarations({ program, env });
    
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0]!.message).toContain("already defined");
  });

  test("detects duplicate type", () => {
    const program = parse(`type Foo
  x: number
type Foo
  y: string`);
    const env = createGlobalEnvironment();
    const result = collectDeclarations({ program, env });
    
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0]!.message).toContain("already defined");
  });

  test("collects type with methods", () => {
    const program = parse(`type Counter
  value: number
  fn increment(): number
    self.value + 1`);
    const env = createGlobalEnvironment();
    const result = collectDeclarations({ program, env });
    
    const counterType = result.env.lookupType("Counter");
    expect(counterType?.kind).toBe("object");
    if (counterType?.kind === "object") {
      expect(counterType.methods.length).toBe(1);
      expect(counterType.methods[0]!.name).toBe("increment");
    }
  });

  test("embed of non-existent type reports error", () => {
    const program = parse(`type Bad
  NoSuchType
  x: number`);
    const env = createGlobalEnvironment();
    const result = collectDeclarations({ program, env });
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors.some(e => e.message.includes("Cannot embed") && e.message.includes("not found"))).toBe(true);
  });

  test("two embeds promoting same member reports ambiguous access", () => {
    const program = parse(`type A
  name: string
type B
  name: string
type C
  A
  B`);
    const env = createGlobalEnvironment();
    const result = collectDeclarations({ program, env });
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors.some(e => e.message.includes("Ambiguous access") && e.message.includes("name"))).toBe(true);
  });
});

describe("Pass 2: Infer Types", () => {
  test("infers literal types", () => {
    const program = parse(`42
"hello"
true`);
    const env = createGlobalEnvironment();
    const { env: populatedEnv, fnDecls } = collectDeclarations({ program, env });
    const result = inferTypes({ program, env: populatedEnv, fnDecls });
    
    expect(result.errors).toHaveLength(0);
    // Types are now stored on AST nodes via resolvedType
    const firstStmt = program.body[0];
    expect(firstStmt?.kind).toBe("ExprStmt");
    if (firstStmt?.kind === "ExprStmt") {
      expect(firstStmt.expr.resolvedType).toBeDefined();
    }
  });

  test("infers binary expression types", () => {
    const program = parse(`1 + 2`);
    const env = createGlobalEnvironment();
    const { env: populatedEnv, fnDecls } = collectDeclarations({ program, env });
    const result = inferTypes({ program, env: populatedEnv, fnDecls });
    
    expect(result.errors).toHaveLength(0);
  });

  test("catches type mismatches", () => {
    const program = parse(`let x: number = "hello"`);
    const env = createGlobalEnvironment();
    const { env: populatedEnv, fnDecls } = collectDeclarations({ program, env });
    const result = inferTypes({ program, env: populatedEnv, fnDecls });
    
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0]!.message).toContain("not assignable");
  });

  test("checks function call arguments", () => {
    const program = parse(`fn add(a: number, b: number): number
  a + b
add("x", "y")`);
    const env = createGlobalEnvironment();
    const { env: populatedEnv, fnDecls } = collectDeclarations({ program, env });
    const result = inferTypes({ program, env: populatedEnv, fnDecls });
    
    expect(result.errors.length).toBeGreaterThan(0);
  });

  test("checks return type", () => {
    const program = parse(`fn getName(): string
  42`);
    const env = createGlobalEnvironment();
    const { env: populatedEnv, fnDecls } = collectDeclarations({ program, env });
    const result = inferTypes({ program, env: populatedEnv, fnDecls });
    
    expect(result.errors.length).toBeGreaterThan(0);
  });
});

describe("Pass 3: Context Analysis", () => {
  test("no errors for simple program", () => {
    const program = parse(`let x = 1`);
    const env = createGlobalEnvironment();
    const { env: populatedEnv, fnDecls } = collectDeclarations({ program, env });
    const result = analyzeContext({ program, env: populatedEnv, fnDecls });
    
    expect(result.errors).toHaveLength(0);
  });
});

describe("Type Utils - Pure Functions", () => {
  test("astTypeToType converts NamedType", () => {
    const namedType = { kind: "NamedType" as const, name: "number", loc: { line: 1, column: 1, offset: 0 } };
    const result = TypeUtils.astTypeToType(namedType);
    expect(result.kind).toBe("number");
  });

  test("astTypeToType converts GenericType", () => {
    const genericType = {
      kind: "GenericType" as const,
      name: "list",
      args: [{ kind: "NamedType" as const, name: "number", loc: { line: 1, column: 1, offset: 0 } }],
      loc: { line: 1, column: 1, offset: 0 }
    };
    const result = TypeUtils.astTypeToType(genericType);
    expect(result.kind).toBe("list");
  });

  test("typesEqual compares primitives", () => {
    expect(TypeUtils.typesEqual(Types.number, Types.number)).toBe(true);
    expect(TypeUtils.typesEqual(Types.number, Types.string)).toBe(false);
  });

  test("typesEqual compares lists", () => {
    const listNum = Types.list(Types.number);
    const listStr = Types.list(Types.string);
    expect(TypeUtils.typesEqual(listNum, listNum)).toBe(true);
    expect(TypeUtils.typesEqual(listNum, listStr)).toBe(false);
  });

  test("findCommonType returns single type", () => {
    const result = TypeUtils.findCommonType([Types.number]);
    expect(result.kind).toBe("number");
  });

  test("findCommonType returns union for different types", () => {
    const result = TypeUtils.findCommonType([Types.number, Types.string]);
    expect(result.kind).toBe("union");
  });

  test("getIterableElementType for list", () => {
    const listType = Types.list(Types.number);
    const result = TypeUtils.getIterableElementType(listType);
    expect(result.kind).toBe("number");
  });

  test("getIterableElementType for string", () => {
    const result = TypeUtils.getIterableElementType(Types.string);
    expect(result.kind).toBe("string");
  });

  test("substituteTypeParams replaces type variables", () => {
    const bindings = new Map<string, typeof Types.number>();
    bindings.set("T", Types.number);
    const typeVar = Types.ref("T");
    const result = TypeUtils.substituteTypeParams(typeVar, bindings);
    expect(result.kind).toBe("number");
  });

  test("getIterableElementType for set, stream, channel", () => {
    expect(TypeUtils.getIterableElementType(Types.set(Types.string)).kind).toBe("string");
    expect(TypeUtils.getIterableElementType(Types.stream(Types.number)).kind).toBe("number");
    expect(TypeUtils.getIterableElementType(Types.channel(Types.bool)).kind).toBe("bool");
  });

  test("formatAstType returns unknown for undefined", () => {
    expect(TypeUtils.formatAstType(undefined)).toBe("unknown");
  });

  test("isAssignable never and intersection", () => {
    const env = createGlobalEnvironment();
    expect(TypeUtils.isAssignable(Types.never, Types.number, env)).toBe(true);
    expect(TypeUtils.isAssignable(Types.number, Types.never, env)).toBe(false);
    const inter = Types.intersection(Types.number, Types.string);
    expect(TypeUtils.isAssignable(inter, Types.number, env)).toBe(true);
  });
});

describe("Type Utils - isAssignable", () => {
  const env = createGlobalEnvironment();

  describe("primitives and unknown/never", () => {
    test("same primitive is assignable", () => {
      expect(TypeUtils.isAssignable(Types.number, Types.number, env)).toBe(true);
      expect(TypeUtils.isAssignable(Types.string, Types.string, env)).toBe(true);
      expect(TypeUtils.isAssignable(Types.bool, Types.bool, env)).toBe(true);
      expect(TypeUtils.isAssignable(Types.null, Types.null, env)).toBe(true);
      expect(TypeUtils.isAssignable(Types.void, Types.void, env)).toBe(true);
    });

    test("different primitives are not assignable", () => {
      expect(TypeUtils.isAssignable(Types.number, Types.string, env)).toBe(false);
      expect(TypeUtils.isAssignable(Types.string, Types.bool, env)).toBe(false);
      expect(TypeUtils.isAssignable(Types.bool, Types.number, env)).toBe(false);
    });

    test("any type is assignable to unknown", () => {
      expect(TypeUtils.isAssignable(Types.number, Types.unknown, env)).toBe(true);
      expect(TypeUtils.isAssignable(Types.string, Types.unknown, env)).toBe(true);
      expect(TypeUtils.isAssignable(Types.unknown, Types.unknown, env)).toBe(true);
    });

    test("unknown is only assignable to unknown", () => {
      expect(TypeUtils.isAssignable(Types.unknown, Types.number, env)).toBe(false);
      expect(TypeUtils.isAssignable(Types.unknown, Types.string, env)).toBe(false);
    });

    test("never is assignable to anything, nothing to never", () => {
      expect(TypeUtils.isAssignable(Types.never, Types.number, env)).toBe(true);
      expect(TypeUtils.isAssignable(Types.never, Types.string, env)).toBe(true);
      expect(TypeUtils.isAssignable(Types.number, Types.never, env)).toBe(false);
    });
  });

  describe("list (invariant)", () => {
    test("same element type is assignable", () => {
      const listNum = Types.list(Types.number);
      expect(TypeUtils.isAssignable(listNum, listNum, env)).toBe(true);
    });

    test("list(unknown) accepts any list", () => {
      expect(TypeUtils.isAssignable(Types.list(Types.number), Types.list(Types.unknown), env)).toBe(true);
    });

    test("different element types are not assignable", () => {
      expect(TypeUtils.isAssignable(Types.list(Types.number), Types.list(Types.string), env)).toBe(false);
      expect(TypeUtils.isAssignable(Types.list(Types.string), Types.list(Types.number), env)).toBe(false);
    });
  });

  describe("map (invariant)", () => {
    test("same key and value type is assignable", () => {
      const m = Types.map(Types.string, Types.number);
      expect(TypeUtils.isAssignable(m, m, env)).toBe(true);
    });

    test("map(unknown,unknown) accepts any map", () => {
      expect(TypeUtils.isAssignable(Types.map(Types.string, Types.number), Types.map(Types.unknown, Types.unknown), env)).toBe(true);
    });

    test("different key or value type is not assignable", () => {
      expect(TypeUtils.isAssignable(Types.map(Types.string, Types.number), Types.map(Types.string, Types.string), env)).toBe(false);
      expect(TypeUtils.isAssignable(Types.map(Types.string, Types.number), Types.map(Types.number, Types.number), env)).toBe(false);
    });
  });

  describe("set (invariant)", () => {
    test("same element type is assignable", () => {
      const setNum = Types.set(Types.number);
      expect(TypeUtils.isAssignable(setNum, setNum, env)).toBe(true);
    });

    test("different element type is not assignable", () => {
      expect(TypeUtils.isAssignable(Types.set(Types.number), Types.set(Types.string), env)).toBe(false);
    });
  });

  describe("channel (invariant)", () => {
    test("same element type is assignable", () => {
      const ch = Types.channel(Types.number);
      expect(TypeUtils.isAssignable(ch, ch, env)).toBe(true);
    });

    test("different element type is not assignable", () => {
      expect(TypeUtils.isAssignable(Types.channel(Types.number), Types.channel(Types.string), env)).toBe(false);
    });
  });

  describe("promise (covariant)", () => {
    test("same resolve type is assignable", () => {
      const p = Types.promise(Types.number);
      expect(TypeUtils.isAssignable(p, p, env)).toBe(true);
    });

    test("source resolve assignable to target resolve is assignable", () => {
      expect(TypeUtils.isAssignable(Types.promise(Types.number), Types.promise(Types.unknown), env)).toBe(true);
    });

    test("target promise(unknown) accepts any promise", () => {
      expect(TypeUtils.isAssignable(Types.promise(Types.string), Types.promise(Types.unknown), env)).toBe(true);
    });

    test("incompatible resolve type is not assignable", () => {
      expect(TypeUtils.isAssignable(Types.promise(Types.string), Types.promise(Types.number), env)).toBe(false);
    });
  });

  describe("stream (covariant)", () => {
    test("same element type is assignable", () => {
      const s = Types.stream(Types.number);
      expect(TypeUtils.isAssignable(s, s, env)).toBe(true);
    });

    test("source element assignable to target element is assignable", () => {
      expect(TypeUtils.isAssignable(Types.stream(Types.number), Types.stream(Types.unknown), env)).toBe(true);
    });
  });

  describe("tuple", () => {
    test("same shape is assignable", () => {
      const t = Types.tuple(Types.number, Types.string);
      expect(TypeUtils.isAssignable(t, t, env)).toBe(true);
    });

    test("different length is not assignable", () => {
      expect(TypeUtils.isAssignable(Types.tuple(Types.number), Types.tuple(Types.number, Types.string), env)).toBe(false);
      expect(TypeUtils.isAssignable(Types.tuple(Types.number, Types.string), Types.tuple(Types.number), env)).toBe(false);
    });

    test("same length different element types is not assignable", () => {
      expect(TypeUtils.isAssignable(Types.tuple(Types.number, Types.string), Types.tuple(Types.string, Types.number), env)).toBe(false);
    });
  });

  describe("optional", () => {
    test("inner type assignable to optional", () => {
      expect(TypeUtils.isAssignable(Types.number, Types.optional(Types.number), env)).toBe(true);
    });

    test("null assignable to optional", () => {
      expect(TypeUtils.isAssignable(Types.null, Types.optional(Types.number), env)).toBe(true);
    });

    test("wrong type not assignable to optional", () => {
      expect(TypeUtils.isAssignable(Types.string, Types.optional(Types.number), env)).toBe(false);
    });
  });

  describe("union", () => {
    test("source assignable to one member of target union", () => {
      const numOrStr = Types.union(Types.number, Types.string);
      expect(TypeUtils.isAssignable(Types.number, numOrStr, env)).toBe(true);
      expect(TypeUtils.isAssignable(Types.string, numOrStr, env)).toBe(true);
    });

    test("source not assignable to any member fails", () => {
      const numOrStr = Types.union(Types.number, Types.string);
      expect(TypeUtils.isAssignable(Types.bool, numOrStr, env)).toBe(false);
    });

    test("union source: all members must be assignable to target", () => {
      const numOrStr = Types.union(Types.number, Types.string);
      expect(TypeUtils.isAssignable(numOrStr, Types.unknown, env)).toBe(true);
      expect(TypeUtils.isAssignable(numOrStr, Types.number, env)).toBe(false);
    });
  });

  describe("intersection", () => {
    test("intersection assignable to each member", () => {
      const inter = Types.intersection(Types.number, Types.string);
      expect(TypeUtils.isAssignable(inter, Types.number, env)).toBe(true);
      expect(TypeUtils.isAssignable(inter, Types.string, env)).toBe(true);
    });

    test("source must be assignable to all members of target intersection", () => {
      const inter = Types.intersection(Types.number, Types.number);
      expect(TypeUtils.isAssignable(Types.number, inter, env)).toBe(true);
    });
  });

  describe("ref and object", () => {
    test("same named type is assignable", () => {
      const pointType = Types.object(
        [Types.prop("x", Types.number), Types.prop("y", Types.number)],
        [],
        "Point"
      );
      const envWithPoint = new TypeEnvironment();
      envWithPoint.defineType("Point", pointType);
      expect(TypeUtils.isAssignable(Types.ref("Point"), Types.ref("Point"), envWithPoint)).toBe(true);
    });

    test("different named types are not assignable", () => {
      const pointType = Types.object(
        [Types.prop("x", Types.number), Types.prop("y", Types.number)],
        [],
        "Point"
      );
      const otherType = Types.object([Types.prop("z", Types.number)], [], "Other");
      const envLocal = new TypeEnvironment();
      envLocal.defineType("Point", pointType);
      envLocal.defineType("Other", otherType);
      expect(TypeUtils.isAssignable(Types.ref("Point"), Types.ref("Other"), envLocal)).toBe(false);
    });
  });

  describe("object to interface (structural)", () => {
    test("object with required methods satisfies interface", () => {
      const closable = env.lookupType("Closable");
      expect(closable?.kind).toBe("interface");
      const objWithClose = Types.object(
        [],
        [{ name: "close", type: Types.fn([], Types.void) }],
        "MyResource"
      );
      expect(TypeUtils.isAssignable(objWithClose, closable!, env)).toBe(true);
    });

    test("object missing interface method does not satisfy", () => {
      const closable = env.lookupType("Closable");
      expect(closable).not.toBeNull();
      const objNoClose = Types.object([Types.prop("x", Types.number)], [], "NoClose");
      expect(TypeUtils.isAssignable(objNoClose, closable!, env)).toBe(false);
    });
  });

  describe("function", () => {
    test("same signature is assignable", () => {
      const fn = Types.fn([Types.param("a", Types.number)], Types.string);
      expect(TypeUtils.isAssignable(fn, fn, env)).toBe(true);
    });

    test("covariant return: subtype return is assignable", () => {
      const fnNum = Types.fn([Types.param("x", Types.number)], Types.number);
      const fnUnknown = Types.fn([Types.param("x", Types.number)], Types.unknown);
      expect(TypeUtils.isAssignable(fnNum, fnUnknown, env)).toBe(true);
    });

    test("contravariant param: target param wider accepts source", () => {
      const fnUnknown = Types.fn([Types.param("x", Types.unknown)], Types.number);
      const fnNum = Types.fn([Types.param("x", Types.number)], Types.number);
      expect(TypeUtils.isAssignable(fnUnknown, fnNum, env)).toBe(true);
    });

    test("source param stricter than target is not assignable", () => {
      const fnNum = Types.fn([Types.param("x", Types.number)], Types.number);
      const fnStr = Types.fn([Types.param("x", Types.string)], Types.number);
      expect(TypeUtils.isAssignable(fnNum, fnStr, env)).toBe(false);
    });
  });

  describe("typevar", () => {
    test("typevar assignable to unknown", () => {
      expect(TypeUtils.isAssignable(Types.typevar("T"), Types.unknown, env)).toBe(true);
    });

    test("anything assignable to typevar (target)", () => {
      expect(TypeUtils.isAssignable(Types.number, Types.typevar("T"), env)).toBe(true);
    });

    test("same typevar name is assignable", () => {
      expect(TypeUtils.isAssignable(Types.typevar("T"), Types.typevar("T"), env)).toBe(true);
    });
  });
});

describe("Type Utils - Pure Functions (continued)", () => {
  test("paramsMatch and contextMatch", () => {
    const p = [Types.param("a", Types.number)];
    expect(TypeUtils.paramsMatch(p, p)).toBe(true);
    expect(TypeUtils.paramsMatch(p, [Types.param("a", Types.string)])).toBe(false);
    const ctx: import("../../src/types/types").ContextBinding[] = [{ name: "x", type: Types.number }];
    expect(TypeUtils.contextMatch(ctx, ctx)).toBe(true);
  });

  test("extendsType Context and typeIsContext", () => {
    const env = createGlobalEnvironment();
    const program = parse(`context Foo
  y: string`);
    const { env: populatedEnv } = collectDeclarations({ program, env });
    const fooType = populatedEnv.lookupType("Foo");
    expect(fooType && TypeUtils.typeIsContext(fooType, populatedEnv)).toBe(true);
    expect(fooType && TypeUtils.extendsType(fooType, "Context", populatedEnv)).toBe(true);
    expect(fooType && (fooType as import("../../src/types/types").ObjectType).isContextType).toBe(true);
  });

  test("isIterable for generic channel/list", () => {
    const genericChannel = Types.generic(Types.ref("Channel"), [Types.number]);
    expect(TypeUtils.isIterable(genericChannel)).toBe(true);
  });

  test("typeInvolvesPromise", () => {
    const env = createGlobalEnvironment();
    expect(TypeUtils.typeInvolvesPromise(Types.promise(Types.number), env)).toBe(true);
    expect(TypeUtils.typeInvolvesPromise(Types.list(Types.promise(Types.number)), env)).toBe(true);
    expect(TypeUtils.typeInvolvesPromise(Types.number, env)).toBe(false);
  });

  test("substituteTypeInObject", () => {
    const objType: import("../../src/types/types").ObjectType = {
      kind: "object",
      name: "Box",
      properties: [{ name: "value", type: Types.ref("T"), optional: false, computed: false, defaultValue: false, embedded: false }],
      methods: [],
    };
    const bindings = new Map<string, import("../../src/types/types").Type>([["T", Types.number]]);
    const result = TypeUtils.substituteTypeInObject(objType, bindings);
    expect(result.properties[0]!.type.kind).toBe("number");
  });

  test("unifyTypes", () => {
    const bindings = new Map<string, import("../../src/types/types").Type>();
    bindings.set("T", Types.unknown);
    TypeUtils.unifyTypes(Types.list(Types.typevar("T")), Types.list(Types.number), bindings);
    expect(bindings.get("T")?.kind).toBe("number");
  });

  test("resolveTypeName", () => {
    const env = createGlobalEnvironment();
    expect(TypeUtils.resolveTypeName("number", env).kind).toBe("number");
    expect(TypeUtils.resolveTypeName("UnknownType", env).kind).toBe("ref");
  });

  test("formatFnSignature and formatMethodSignature", () => {
    const program = parse(`fn add(a: number, b: number): number
  a + b`);
    const fnDecl = program.body.find((s): s is import("../../src/parser/ast").FnDecl => s.kind === "FnDecl")!;
    const sig = TypeUtils.formatFnSignature(fnDecl);
    expect(sig).toContain("number");
    expect(sig).toContain("add");
    const typeProgram = parse(`type T
  fn m(x: number): string
    "ok"`);
    const typeDecl = typeProgram.body.find((s): s is import("../../src/parser/ast").TypeDecl => s.kind === "TypeDecl")!;
    const method = typeDecl.body!.members.find((m): m is import("../../src/parser/ast").MethodDecl => m.kind === "MethodDecl")!;
    expect(TypeUtils.formatMethodSignature(method)).toContain("number");
  });

  test("formatTypeSignature", () => {
    const program = parse(`type Point
  x: number
  y: number`);
    const typeDecl = program.body.find((s): s is import("../../src/parser/ast").TypeDecl => s.kind === "TypeDecl")!;
    const { signature, fields } = TypeUtils.formatTypeSignature(typeDecl);
    expect(signature).toContain("Point");
    expect(fields.length).toBe(2);
  });
});

describe("Integration - PassManager matches TypeChecker", () => {
  // These tests verify the new PassManager produces same results as original

  test("variable scoping", () => {
    const result = checkWithPassManager(`let x = 1
x + 1`);
    expect(result.errors).toHaveLength(0);
  });

  test("function calls", () => {
    const result = checkWithPassManager(`fn double(x: number): number
  x * 2
double(5)`);
    expect(result.errors).toHaveLength(0);
  });

  test("type declarations", () => {
    const result = checkWithPassManager(`type Point
  x: number
  y: number
let p = Point(1, 2)
p.x + p.y`);
    expect(result.errors).toHaveLength(0);
  });

  test("control flow", () => {
    const result = checkWithPassManager(`let x = 1
if x > 0
  x + 1
else
  x - 1`);
    expect(result.errors).toHaveLength(0);
  });

  test("for loop", () => {
    const result = checkWithPassManager(`for i in [1, 2, 3]
  i + 1`);
    expect(result.errors).toHaveLength(0);
  });

  test("match statement", () => {
    const result = checkWithPassManager(`let x = 1
match x
  1 => "one"
  _ => "other"`);
    expect(result.errors).toHaveLength(0);
  });

  test("lambda expressions", () => {
    const result = checkWithPassManager(`let add = (a: number, b: number) => a + b
add(1, 2)`);
    expect(result.errors).toHaveLength(0);
  });

  test("list operations", () => {
    const result = checkWithPassManager(`let nums = [1, 2, 3]
nums.push(4)
nums.length`);
    expect(result.errors).toHaveLength(0);
  });

  test("map operations", () => {
    const result = checkWithPassManager(`let m = {a: 1, b: 2}
m["a"]`);
    expect(result.errors).toHaveLength(0);
  });
});

describe("PassManager - Configurable API", () => {
  test("createDefault includes all standard passes", () => {
    const mgr = PassManager.createDefault();
    const names = mgr.getPassNames();
    expect(names).toContain("collect-declarations");
    expect(names).toContain("infer-types");
    expect(names).toContain("context-analysis");
  });

  test("addPass appends to pipeline", () => {
    const mgr = new PassManager();
    mgr.addPass(new CollectDeclarationsPass());
    mgr.addPass(new InferTypesPass());
    expect(mgr.getPassNames()).toEqual(["collect-declarations", "infer-types"]);
  });

  test("removePass removes by name", () => {
    const mgr = PassManager.createDefault();
    mgr.removePass("context-analysis");
    expect(mgr.getPassNames()).toEqual(["collect-declarations", "infer-types"]);
  });

  test("insertBefore inserts at correct position", () => {
    const mgr = new PassManager();
    mgr.addPass(new CollectDeclarationsPass());
    mgr.addPass(new ContextAnalysisPass());
    mgr.insertBefore("context-analysis", new InferTypesPass());
    expect(mgr.getPassNames()).toEqual(["collect-declarations", "infer-types", "context-analysis"]);
  });

  test("insertAfter inserts at correct position", () => {
    const mgr = new PassManager();
    mgr.addPass(new CollectDeclarationsPass());
    mgr.addPass(new ContextAnalysisPass());
    mgr.insertAfter("collect-declarations", new InferTypesPass());
    expect(mgr.getPassNames()).toEqual(["collect-declarations", "infer-types", "context-analysis"]);
  });

  test("custom pass can be added", () => {
    let customRan = false;
    const customPass: Pass = {
      name: "custom-pass",
      run(ctx: PassContext) {
        customRan = true;
      }
    };

    const mgr = PassManager.createDefault();
    mgr.addPass(customPass);
    
    const program = parse("let x = 1");
    mgr.run(program);
    
    expect(customRan).toBe(true);
    expect(mgr.getPassNames()).toContain("custom-pass");
  });

  test("pipeline without infer-types pass still runs", () => {
    const mgr = new PassManager();
    mgr.addPass(new CollectDeclarationsPass());
    // Intentionally skip InferTypesPass
    
    const program = parse(`fn add(a: number, b: number): number
  a + b`);
    const result = mgr.run(program);
    
    // Should have no errors (but also no type checking)
    expect(result.errors).toHaveLength(0);
    // Without InferTypesPass, AST nodes won't have resolvedType set
    const fnDecl = result.program.body[0];
    expect(fnDecl?.kind).toBe("FnDecl");
    if (fnDecl?.kind === "FnDecl") {
      expect(fnDecl.resolvedType).toBeUndefined();
    }
  });

  test("method chaining works", () => {
    const mgr = new PassManager()
      .addPass(new CollectDeclarationsPass())
      .addPass(new InferTypesPass())
      .removePass("infer-types")
      .addPass(new InferTypesPass());
    
    expect(mgr.getPassNames()).toEqual(["collect-declarations", "infer-types"]);
  });
});
