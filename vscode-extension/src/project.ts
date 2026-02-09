import { findMsToml, loadMsToml, type MsTomlConfig } from "../../src/modules";
import type { CompileHost } from "../../src/shared/host";

export async function getProjectConfig(
  filePath: string,
  host: CompileHost
): Promise<{ projectRoot: string; config: MsTomlConfig } | null> {
  const startDir = host.dirname(host.resolvePath(filePath));
  const projectRoot = await findMsToml(host, startDir);
  if (!projectRoot) return null;
  try {
    const config = await loadMsToml(host, projectRoot);
    return { projectRoot, config };
  } catch {
    return null;
  }
}
