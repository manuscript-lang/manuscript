// conform: tags=control-flow,faults,formatter,interpolation,modules,stdlib-faults,testing,tier-stdlib
// conform: phase=test,parse
// conform: origin=pkg/parser/parser_test.go:60 FuzzParse
import panic from "@std/core.ms"

test "text" {
	if not (f"{1}" == "1") {
		return panic(message: "check failed")
	}
}
