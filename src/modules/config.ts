import * as fs from "fs/promises";
import * as path from "path";

export interface MsTomlConfig {
  projectRoot: string;
  srcDir: string;
}

const DEFAULT_SRC = "src";
const MS_TOML = "ms.toml";

function parseSrcFromToml(content: string): string {
  const line = content
    .split("\n")
    .map((l) => l.replace(/#.*/, "").trim())
    .find((l) => l.startsWith("src"));
  if (!line) return DEFAULT_SRC;
  const match = line.match(/src\s*=\s*"([^"]+)"/);
  return match ? match[1]! : DEFAULT_SRC;
}

export async function findMsToml(startDir: string): Promise<string | null> {
  let dir = path.resolve(startDir);
  const root = path.parse(dir).root;
  while (true) {
    const candidate = path.join(dir, MS_TOML);
    try {
      await fs.access(candidate);
      return dir;
    } catch {
      if (dir === root) return null;
      dir = path.dirname(dir);
    }
  }
}

export async function loadMsToml(projectRoot: string): Promise<MsTomlConfig> {
  const tomlPath = path.join(projectRoot, MS_TOML);
  let content: string;
  try {
    content = await fs.readFile(tomlPath, "utf-8");
  } catch (e) {
    throw new Error(`Cannot read ${tomlPath}: ${(e as Error).message}`);
  }
  const srcDirName = parseSrcFromToml(content);
  const srcDir = path.join(projectRoot, srcDirName);
  try {
    const stat = await fs.stat(srcDir);
    if (!stat.isDirectory()) {
      throw new Error(`ms.toml: src "${srcDirName}" is not a directory`);
    }
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code === "ENOENT") {
      throw new Error(`ms.toml: src directory "${srcDirName}" does not exist`);
    }
    throw e;
  }
  return { projectRoot, srcDir };
}
