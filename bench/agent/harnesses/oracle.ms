import Harness, Usage from "./harness.ms"

// Not an agent: the runner copies the reference solution in. Used to validate challenges and tests.
export type Oracle:
	placeholder: Bool = true

fn Oracle.name() String: "oracle"

fn Oracle.command(prompt: String, model: String?, workspace: String) List[String]: [
	"true"
]

fn Oracle.parse(transcript: String) Usage: Usage()
