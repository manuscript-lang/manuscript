import * as path from "path";
import { fileURLToPath } from "node:url";
import { findMsToml, loadMsToml, resolveSpecifier } from "../../src/modules";

export async function getProjectConfig(
  fileUri: string
): Promise<{ projectRoot: string; config: Awaited<ReturnType<typeof loadMsToml>> } | null> {
  const entryPath = fileURLToPath(new URL(fileUri));
  const projectRoot = await findMsToml(path.dirname(entryPath));
  if (!projectRoot) return null;
  try {
    const config = await loadMsToml(projectRoot);
    return { projectRoot, config };
  } catch {
    return null;
  }
}

export async function resolveLocalImport(
  fileUri: string,
  specifier: string
): Promise<{ path: string } | null> {
  const proj = await getProjectConfig(fileUri);
  if (!proj) return null;
  const resolved = resolveSpecifier(proj.projectRoot, proj.config.srcDir, specifier);
  if (!("kind" in resolved) || resolved.kind !== "local") return null;
  return { path: resolved.path };
}
