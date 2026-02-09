/**
 * Node-backed CompileHost. Only used by CLI and tests; built here and passed down.
 * LSP/server builds its own host (using this for the base, or reimplementing).
 */
import * as fs from "fs/promises";
import * as path from "path";
import type { CompileHost } from "../shared/host";

export function createNodeHost(overrides?: Partial<CompileHost>): CompileHost {
  return {
    resolvePath: (p) => path.resolve(p),
    joinPaths: (a, b) => path.join(a, b),
    dirname: (p) => path.dirname(p),
    relative: (from, to) => path.relative(from, to),
    parseRoot: (p) => path.parse(path.resolve(p)).root,
    pathSep: path.sep,
    readFile: (p) => fs.readFile(path.resolve(p), "utf-8"),
    fileExists: async (p) => {
      try {
        await fs.access(path.resolve(p));
        return true;
      } catch {
        return false;
      }
    },
    stat: async (p) => {
      const s = await fs.stat(path.resolve(p));
      return { isDirectory: () => s.isDirectory() };
    },
    ...overrides,
  };
}
