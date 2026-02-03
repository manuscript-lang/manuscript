// Stdlib module - imports source from stdlib.ms at build time
import stdlibSourceContent from "./stdlib.ms" with { type: "text" };
import { Parser } from "../parser";
import type * as AST from "../parser/ast";

export const STDLIB_PATH_URI = `manuscript://stdlib.ms`;
export const stdlibSource = stdlibSourceContent;

// Cache parsed stdlib AST
let stdlibASTCache: AST.Program | null = null;

export function getStdlibAST(): AST.Program {
  if (!stdlibASTCache) {
    stdlibASTCache = new Parser(stdlibSource).parse();
  }
  return stdlibASTCache;
}
