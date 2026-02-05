import { describe, test, expect } from "bun:test";
import * as fs from "fs/promises";
import * as path from "path";
import { compileProject } from "../../src/cli/compiler";
import { findMsToml, loadMsToml, buildModuleGraph, resolveSpecifier } from "../../src/modules";

describe("E2E: Multi-file and imports", () => {
  test("compileProject: two files with import", async () => {
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
    const result = await compileProject(entryPath, { typeCheck: true });
    expect(result.success).toBe(true);
    expect(result.outputs.size).toBe(2);
    const mainCode = result.outputs.get(path.resolve(entryPath));
    expect(mainCode).toBeDefined();
    expect(mainCode).toContain("lib");
    expect(mainCode).toContain("add");
    await fs.rm(dir, { recursive: true, force: true });
  });

  test("compileProject with outDir writes .js files", async () => {
    const dir = path.join(process.cwd(), "tests", "e2e", "fixtures", "multi-file-out");
    const outDir = path.join(dir, "out");
    await fs.mkdir(dir, { recursive: true });
    await fs.writeFile(path.join(dir, "ms.toml"), 'src = "."\n');
    await fs.writeFile(path.join(dir, "lib.ms"), "fn id(x: number): number\n  x\n");
    await fs.writeFile(path.join(dir, "main.ms"), 'import { id } from "lib"\nprint(id(42))\n');
    const result = await compileProject(path.join(dir, "main.ms"), {
      typeCheck: true,
      outDir,
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
    const projectRoot = await findMsToml(process.cwd());
    expect(projectRoot).toBe(process.cwd());
    const config = await loadMsToml(projectRoot!);
    expect(config.projectRoot).toBe(process.cwd());
    expect(config.srcDir).toBe(process.cwd());
  });

  test("resolveSpecifier: logical path", () => {
    const result = resolveSpecifier("/proj", "/proj/src", "lib/foo");
    expect("kind" in result && result.kind === "local").toBe(true);
    if ("kind" in result && result.kind === "local") {
      expect(result.path).toContain("lib");
      expect(result.path).toContain("foo.ms");
    }
  });

  test("resolveSpecifier: relative rejected", () => {
    const result = resolveSpecifier("/proj", "/proj/src", "./lib");
    expect("message" in result).toBe(true);
    expect((result as { message: string }).message).toContain("Relative");
  });

  test("resolveSpecifier: pkg external", () => {
    const result = resolveSpecifier("/proj", "/proj/src", "pkg:utils");
    expect(result).toEqual({ kind: "external" });
  });

  test("compileProject: unresolved module errors on importer file with line", async () => {
    const dir = path.join(process.cwd(), "tests", "e2e", "fixtures", "multi-file-unresolved");
    await fs.mkdir(dir, { recursive: true });
    await fs.writeFile(path.join(dir, "ms.toml"), 'src = "."\n');
    await fs.writeFile(
      path.join(dir, "main.ms"),
      'import { add } from "nonexistent"\nlet x = 1\n'
    );
    const entryPath = path.join(dir, "main.ms");
    const result = await compileProject(entryPath, { typeCheck: true });
    expect(result.success).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    const moduleError = result.errors.find((e) => e.message.includes("Module not found") || e.message.includes("not found"));
    expect(moduleError).toBeDefined();
    expect(path.resolve(moduleError!.file!)).toBe(path.resolve(entryPath));
    expect(moduleError!.line).toBe(1);
    await fs.rm(dir, { recursive: true, force: true });
  });
});
