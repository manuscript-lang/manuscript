import * as path from "path";
import { findMsToml, loadMsToml } from "../../src/modules";

export async function getProjectConfig(
  filePath: string
): Promise<{ projectRoot: string; config: Awaited<ReturnType<typeof loadMsToml>> } | null> {
  const projectRoot = await findMsToml(path.dirname(path.resolve(filePath)));
  if (!projectRoot) return null;
  try {
    const config = await loadMsToml(projectRoot);
    return { projectRoot, config };
  } catch {
    return null;
  }
}
