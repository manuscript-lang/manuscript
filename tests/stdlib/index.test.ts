import { describe, test, expect } from "bun:test";
import { getStdlibAST } from "../../src/stdlib";
import { isBuiltin, EXTERN_TYPES } from "../../src/shared/stdlib";

describe("Stdlib", () => {
  test("getStdlibAST returns parsed program and caches on second call", () => {
    const ast = getStdlibAST();
    expect(ast.body.length).toBeGreaterThan(0);
    expect(getStdlibAST()).toBe(ast);
  });

  test("isBuiltin identifies stdlib functions, primitives, extern types, and rejects unknown", () => {
    expect(isBuiltin("print")).toBe(true);
    expect(isBuiltin("number")).toBe(true);
    expect(isBuiltin("NotABuiltinName123")).toBe(false);
    if (EXTERN_TYPES.size > 0) {
      expect(isBuiltin([...EXTERN_TYPES][0]!)).toBe(true);
    }
  });
});
