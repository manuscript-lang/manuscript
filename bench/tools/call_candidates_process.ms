// Bash's built-in timer supplies child user/system CPU time without an external time binary.
import Ran, capture, invalid from "./lib.ms"

export type Timed:
	result: Ran
	user_ns: Float
	system_ns: Float
	// Executable followed by one exact argument per line.
	command: String

export fn timed(program: String, arguments: List[String]) Timed!:
	command := [
		"-c", "export LC_ALL=C; TIMEFORMAT='CALL_CPU %U %S'; time \"$@\"",
		"call-candidate-timer", program.clone()
	].concat(arguments)
	ran := capture("bash", command)

	for line in ran.stderr.split("\n"):
		if not line.starts_with("CALL_CPU "): continue

		parts := line.split(" ")
		return ok(
			Timed(
				ran, parts[1].parse_float().get() * 1000000000.0,
				parts[2].parse_float().get() * 1000000000.0,
				"bash\n" + command.join("\n") + "\n"
			)
		)

	return invalid("child CPU timer did not report its result")
