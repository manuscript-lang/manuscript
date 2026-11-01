import Harness from "./harness.ms"
import ClaudeCode from "./claude_code.ms"
import Codex from "./codex.ms"
import Oracle from "./oracle.ms"
import Pi from "./pi.ms"

export fn names() List[String]: ["claude_code", "codex", "oracle", "pi"]

# The harness registered under `name`.
export fn find(name: String) Harness?:
    if name == "claude_code": return ClaudeCode()
    if name == "codex": return Codex()
    if name == "oracle": return Oracle()
    if name == "pi": return Pi()

    return none
