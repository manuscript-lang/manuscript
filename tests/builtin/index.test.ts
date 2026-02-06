import { describe, test, expect } from "bun:test";
import { getBuiltinsAST } from "../../src/builtin";
import { isBuiltin, EXTERN_TYPES } from "../../src/shared/stdlib";

describe("Builtin", () => {
  test("getBuiltinsAST returns parsed program and caches on second call", () => {
    const ast = getBuiltinsAST();
    expect(ast.body.length).toBeGreaterThan(0);
    expect(getBuiltinsAST()).toBe(ast);
  });

  test("isBuiltin identifies builtin functions, primitives, extern types, and rejects unknown", () => {
    expect(isBuiltin("print")).toBe(true);
    expect(isBuiltin("number")).toBe(true);
    expect(isBuiltin("NotABuiltinName123")).toBe(false);
    if (EXTERN_TYPES.size > 0) {
      expect(isBuiltin([...EXTERN_TYPES][0]!)).toBe(true);
    }
  });
});
