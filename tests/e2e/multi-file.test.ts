import { describe, test, expect } from "bun:test";
import * as fs from "fs/promises";
import * as path from "path";
import { compileEntry } from "../../src/compile";
import { findMsToml, loadMsToml, resolveSpecifier } from "../../src/modules";
import { createNodeHost } from "../../src/cli/host";

describe("E2E: Multi-file and imports", () => {
  test("compileEntry: two files with import", async () => {
    const dir = path.join(process.cwd(), "tests", "e2e", "fixtures", "multi-file-project");
    await fs.mkdir(dir, { recursive: true });
    await fs.writeFile(
      path.join(dir, "ms.toml"),
      'src = "."\n'
    );
    await fs.writeFile(
      path.join(dir, "lib.ms"),
      `fn add(a: number, b: number): number
  a + b
`
    );
    await fs.writeFile(
      path.join(dir, "main.ms"),
      `import { add } from "lib"
let x = add(1, 2)
print(x)
`
    );
    const entryPath = path.join(dir, "main.ms");
    const host = createNodeHost();
    const result = await compileEntry(entryPath, { host, typeCheck: true });
    expect(result.success).toBe(true);
    expect(result.outputs.size).toBe(2);
    const mainCode = result.outputs.get(path.resolve(entryPath));
    expect(mainCode).toBeDefined();
    expect(mainCode).toContain("lib");
    expect(mainCode).toContain("add");
    await fs.rm(dir, { recursive: true, force: true });
  });

  test("compileEntry with outDir writes .js files", async () => {
    const dir = path.join(process.cwd(), "tests", "e2e", "fixtures", "multi-file-out");
    const outDir = path.join(dir, "out");
    await fs.mkdir(dir, { recursive: true });
    await fs.writeFile(path.join(dir, "ms.toml"), 'src = "."\n');
    await fs.writeFile(path.join(dir, "lib.ms"), "fn id(x: number): number\n  x\n");
    await fs.writeFile(path.join(dir, "main.ms"), 'import { id } from "lib"\nprint(id(42))\n');
    const host = createNodeHost();
    const result = await compileEntry(path.join(dir, "main.ms"), {
      host,
      typeCheck: true,
      outDir,
      writeFile: (p, c) => fs.writeFile(path.resolve(p), c, "utf-8"),
      mkdir: async (p, opts) => {
        await fs.mkdir(path.resolve(p), opts as { recursive?: boolean });
      },
    });
    expect(result.success).toBe(true);
    const mainJs = path.join(outDir, "main.js");
    const libJs = path.join(outDir, "lib.js");
    const mainContent = await fs.readFile(mainJs, "utf-8");
    const libContent = await fs.readFile(libJs, "utf-8");
    expect(mainContent).toContain("lib");
    expect(libContent).toContain("function");
    await fs.rm(dir, { recursive: true, force: true });
  });

  test("findMsToml and loadMsToml", async () => {
    const host = createNodeHost();
    const projectRoot = await findMsToml(host, process.cwd());
    expect(projectRoot).toBe(process.cwd());
    const config = await loadMsToml(host, projectRoot!);
    expect(config.projectRoot).toBe(process.cwd());
    expect(config.srcDir).toBe(process.cwd());
  });

  test("resolveSpecifier: logical path", () => {
    const host = createNodeHost();
    const result = resolveSpecifier(host, "/proj", "/proj/src", "lib/foo");
    expect("kind" in result && result.kind === "local").toBe(true);
    if ("kind" in result && result.kind === "local") {
      expect(result.path).toContain("lib");
      expect(result.path).toContain("foo.ms");
    }
  });

  test("resolveSpecifier: relative rejected", () => {
    const host = createNodeHost();
    const result = resolveSpecifier(host, "/proj", "/proj/src", "./lib");
    expect("message" in result).toBe(true);
    expect((result as { message: string }).message).toContain("Relative");
  });

  test("resolveSpecifier: pkg external", () => {
    const host = createNodeHost();
    const result = resolveSpecifier(host, "/proj", "/proj/src", "pkg:utils");
    expect(result).toEqual({ kind: "external" });
  });

  test("compileEntry: unresolved module errors on importer file with line", async () => {
    const dir = path.join(process.cwd(), "tests", "e2e", "fixtures", "multi-file-unresolved");
    await fs.mkdir(dir, { recursive: true });
    await fs.writeFile(path.join(dir, "ms.toml"), 'src = "."\n');
    await fs.writeFile(
      path.join(dir, "main.ms"),
      'import { add } from "nonexistent"\nlet x = 1\n'
    );
    const entryPath = path.join(dir, "main.ms");
    const host = createNodeHost();
    const result = await compileEntry(entryPath, { host, typeCheck: true });
    expect(result.success).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    const moduleError = result.errors.find((e) => e.message.includes("Module not found") || e.message.includes("not found"));
    expect(moduleError).toBeDefined();
    expect(path.resolve(moduleError!.file!)).toBe(path.resolve(entryPath));
    expect(moduleError!.line).toBe(1);
    await fs.rm(dir, { recursive: true, force: true });
  });
});
