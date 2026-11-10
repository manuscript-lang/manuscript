import (
	Harness from "./harness.ms",
	ClaudeCode from "./claude_code.ms",
	Codex from "./codex.ms",
	Oracle from "./oracle.ms",
	Pi from "./pi.ms",
)

export fn names() List[String]: ["claude_code", "codex", "oracle", "pi"]

// The harness registered under `name`.
export fn find(name: String) Harness?:
	if name == "claude_code": return ClaudeCode()
	if name == "codex": return Codex()
	if name == "oracle": return Oracle()
	if name == "pi": return Pi()

	return none
