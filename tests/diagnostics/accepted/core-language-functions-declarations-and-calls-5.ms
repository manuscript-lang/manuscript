// conform: tags=control-flow,diagnostics,faults,formatter,modules,stdlib-faults,tier-stdlib
// conform: phase=check,parse
// conform: origin=documentation/core-language/functions/declarations-and-calls.md:116
import panic from "@std/core.ms"

fn check_positive(value Int) Void {
	if not (value > 0) {
		return panic(message: "check failed")
	}
}

fn missing_value() Int {
	return panic(message: "Required value is missing")
}
// expect-exit: 0
