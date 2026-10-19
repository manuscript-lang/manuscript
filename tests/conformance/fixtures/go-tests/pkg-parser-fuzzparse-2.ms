# conform: tags=control-flow,faults,interpolation,modules,stdlib-faults,testing,tier-stdlib
# conform: phase=test
# conform: origin=pkg/parser/parser_test.go:60 FuzzParse
import panic from "@std/faults.ms"

test "text":
    if not ("{1}" == "1"):
        return panic(message: "check failed")
