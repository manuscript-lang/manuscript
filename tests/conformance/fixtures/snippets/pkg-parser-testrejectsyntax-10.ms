# conform: tags=control-flow,faults,modules,parser,stdlib-faults,testing,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:43 TestRejectSyntax
import panic from "@std/faults.ms"

test "bad":
    if not ("\q" == ""):
        return panic(message: "check failed")
