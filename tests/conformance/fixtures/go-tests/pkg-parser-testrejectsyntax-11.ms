# conform: tags=control-flow,faults,interpolation,modules,parser,stdlib-faults,testing,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:44 TestRejectSyntax
import panic from "@std/faults.ms"

test "bad":
    if not ("\u{D800}" == ""):
        return panic(message: "check failed")
