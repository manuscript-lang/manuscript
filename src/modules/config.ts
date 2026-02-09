import type { CompileHost } from "../shared/host";

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

export async function findMsToml(host: CompileHost, startDir: string): Promise<string | null> {
  let dir = host.resolvePath(startDir);
  const root = host.parseRoot(dir);
  while (true) {
    const candidate = host.joinPaths(dir, MS_TOML);
    const exists = await host.fileExists(candidate);
    if (exists) return dir;
    if (dir === root) return null;
    dir = host.dirname(dir);
  }
}

export async function loadMsToml(host: CompileHost, projectRoot: string): Promise<MsTomlConfig> {
  const tomlPath = host.joinPaths(projectRoot, MS_TOML);
  let content: string;
  try {
    content = await host.readFile(tomlPath);
  } catch (e) {
    throw new Error(`Cannot read ${tomlPath}: ${(e as Error).message}`);
  }
  const srcDirName = parseSrcFromToml(content);
  const srcDir = host.joinPaths(projectRoot, srcDirName);
  try {
    const stat = await host.stat(srcDir);
    if (!stat.isDirectory()) {
      throw new Error(`ms.toml: src "${srcDirName}" is not a directory`);
    }
  } catch (e) {
    const err = e as Error & { code?: string };
    if (err?.code === "ENOENT") {
      throw new Error(`ms.toml: src directory "${srcDirName}" does not exist`);
    }
    throw e;
  }
  return { projectRoot, srcDir };
}
