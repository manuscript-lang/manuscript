import Harness, Usage from "./harness.ms"

# Not an agent: the runner copies the reference solution in. Used to validate challenges and tests.
export type Oracle:
    placeholder: Bool = true

impl Harness for Oracle:
    fn name() String: "oracle"

    fn command(prompt: String, model: String?, workspace: String) List[String]: ["true"]

    fn parse(transcript: String) Usage: Usage()
