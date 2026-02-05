import { describe, test, expect } from "bun:test";
import {
  getTypeMemberCompletions,
  getObjectMemberCompletions,
  getScopeCompletions,
  resolveObjectType,
} from "../../src/lsp";
import type { TypeMemberInfo } from "../../src/stdlib/extractor";

const dummyLoc = { line: 1, column: 0, offset: 0 };
import { Parser } from "../../src/parser";
import { TypeChecker } from "../../src/types";

describe("LSP Completions", () => {
  describe("getTypeMemberCompletions", () => {
    test("returns empty for missing or empty type members", () => {
      expect(getTypeMemberCompletions(new Map(), "string")).toEqual([]);
      const map = new Map<string, TypeMemberInfo[]>([["list", [{ name: "push", kind: "method", signature: "push(x)", loc: dummyLoc }]]]);
      expect(getTypeMemberCompletions(map, "string")).toEqual([]);
    });

    test("returns property and method completions with label, kind, detail, doc", () => {
      const loc = { line: 1, column: 0, offset: 0 };
      const typeMembers = new Map<string, TypeMemberInfo[]>([
        [
          "string",
          [
            { name: "length", kind: "field", signature: "number", loc: dummyLoc },
            { name: "upper", kind: "method", signature: "fn(): string", doc: "Uppercase", loc: dummyLoc },
          ],
        ],
      ]);
      const result = getTypeMemberCompletions(typeMembers, "string");
      expect(result).toHaveLength(2);
      expect(result[0]).toEqual({ label: "length", kind: "property", detail: "number" });
      expect(result[1]).toEqual({ label: "upper", kind: "method", detail: "fn(): string", doc: "Uppercase" });
    });
  });

  describe("getObjectMemberCompletions", () => {
    test("returns properties and methods, empty for no members", () => {
      const obj = {
        kind: "object" as const,
        name: "Person",
        properties: [{ name: "name", type: { kind: "string" } as any, optional: false, computed: false, defaultValue: false }],
        methods: [
          {
            name: "greet",
            type: {
              kind: "function",
              params: [],
              returnType: { kind: "string" },
              context: [],
            } as any,
          },
        ],
      };
      const result = getObjectMemberCompletions(obj);
      expect(result).toHaveLength(2);
      expect(result[0]).toMatchObject({ label: "name", kind: "property" });
      expect(result[1]).toMatchObject({ label: "greet", kind: "method" });
      expect(getObjectMemberCompletions({ kind: "object" as const, name: "Empty", properties: [], methods: [] })).toEqual([]);
    });
  });

  describe("getScopeCompletions", () => {
    test("includes function and type decls with types", () => {
      const source = `
fn add(a: number, b: number): number
  return a + b
type T
  x: number
`;
      const parser = new Parser(source);
      const program = parser.parse();
      const checker = new TypeChecker();
      const result = checker.check(program);
      const completions = getScopeCompletions(program, result.types, 10);
      expect(completions.some((c) => c.label === "add" && c.kind === "function")).toBe(true);
      expect(completions.some((c) => c.label === "T" && c.kind === "type")).toBe(true);
    });

    test("includes let and var from earlier lines", () => {
      const source = `
let x = 1
var y = 2
let z = x + y
`;
      const parser = new Parser(source);
      const program = parser.parse();
      const checker = new TypeChecker();
      const result = checker.check(program);
      const completions = getScopeCompletions(program, result.types, 5);
      expect(completions.some((c) => c.label === "x" && c.kind === "variable")).toBe(true);
      expect(completions.some((c) => c.label === "y" && c.kind === "variable")).toBe(true);
    });

    test("excludes let/var on same or later line", () => {
      const source = `let a = 1`;
      const parser = new Parser(source);
      const program = parser.parse();
      const checker = new TypeChecker();
      const result = checker.check(program);
      const completions = getScopeCompletions(program, result.types, 1);
      expect(completions.filter((c) => c.label === "a")).toHaveLength(0);
    });

    test("uses short function signature when type not in map", () => {
      const source = `fn add(a: number, b: number): number\n  return a + b`;
      const parser = new Parser(source);
      const program = parser.parse();
      const emptyTypes = new Map();
      const completions = getScopeCompletions(program, emptyTypes, 5);
      const fnCompletion = completions.find((c) => c.label === "add" && c.kind === "function");
      expect(fnCompletion).toBeDefined();
      expect(fnCompletion!.detail).toContain("fn(");
      expect(fnCompletion!.detail).toContain("number");
    });
  });
});
