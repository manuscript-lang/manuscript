// Builtins module - imports source from builtins.ms at build time
import builtinsSourceContent from "./builtins.ms" with { type: "text" };
import { Parser } from "../parser";
import type * as AST from "../parser/ast";

export const BUILTINS_PATH_URI = `manuscript://builtins.ms`;
export const builtinsSource = builtinsSourceContent;

let builtinsASTCache: AST.Program | null = null;

export function getBuiltinsAST(): AST.Program {
  if (!builtinsASTCache) {
    builtinsASTCache = new Parser(builtinsSource).parse();
  }
  return builtinsASTCache;
}
