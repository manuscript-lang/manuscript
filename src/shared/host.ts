/**
 * Host abstraction for path and file I/O. Injected from CLI/LSP so core compile/types/modules
 * do not depend on Node fs/path. CLI provides a Node-backed host; LSP can use its own.
 */
export interface CompileHost {
  resolvePath(p: string): string;
  joinPaths(a: string, b: string): string;
  dirname(p: string): string;
  relative(from: string, to: string): string;
  parseRoot(p: string): string;
  pathSep: string;
  readFile(p: string): Promise<string>;
  fileExists(p: string): Promise<boolean>;
  stat(p: string): Promise<{ isDirectory(): boolean }>;
}
