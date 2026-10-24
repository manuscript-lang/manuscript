# conform: tags=control-flow,faults,formatter,interpolation,modules,parser,stdlib-faults,testing,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:60 FuzzParse
from "@std/core.ms" import panic

test "text":
    if not (f"{1}" == "1"):
        return panic(message: "check failed")
