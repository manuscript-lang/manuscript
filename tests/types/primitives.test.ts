import { describe, test, expect } from "bun:test";
import {
  createBuiltinMethodRegistry,
  resolvePrimitiveType,
  constructGenericType,
  PRIMITIVE_TYPE_MAP,
  GENERIC_TYPE_CONSTRUCTORS,
} from "../../src/types/primitives";
import { Types } from "../../src/types/types";

describe("primitives", () => {
  test("createBuiltinMethodRegistry returns empty Map", () => {
    const reg = createBuiltinMethodRegistry();
    expect(reg).toBeInstanceOf(Map);
    expect(reg.size).toBe(0);
  });

  test("resolvePrimitiveType returns type for known primitives", () => {
    expect(resolvePrimitiveType("number")?.kind).toBe("number");
    expect(resolvePrimitiveType("string")?.kind).toBe("string");
    expect(resolvePrimitiveType("bool")?.kind).toBe("bool");
    expect(resolvePrimitiveType("null")?.kind).toBe("null");
    expect(resolvePrimitiveType("any")?.kind).toBe("any");
    expect(resolvePrimitiveType("Unknown")).toBeUndefined();
  });

  test("constructGenericType builds list, map, set", () => {
    expect(constructGenericType("list", [Types.number])?.kind).toBe("list");
    expect(constructGenericType("map", [Types.string, Types.number])?.kind).toBe("map");
    expect(constructGenericType("set", [Types.string])?.kind).toBe("set");
    expect(constructGenericType("Promise", [Types.number])?.kind).toBe("promise");
    expect(constructGenericType("unknown", [Types.number])).toBeUndefined();
    expect(constructGenericType("list", [])).toBeUndefined();
  });

  test("PRIMITIVE_TYPE_MAP and GENERIC_TYPE_CONSTRUCTORS are defined", () => {
    expect(PRIMITIVE_TYPE_MAP["number"]).toBeDefined();
    expect(GENERIC_TYPE_CONSTRUCTORS["list"]).toBeDefined();
  });
});
