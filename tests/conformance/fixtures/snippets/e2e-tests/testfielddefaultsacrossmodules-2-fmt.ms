# conform: tags=control-flow,faults,formatter,modules,parser,stdlib-testing,testing,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/e2e_test.go:547 TestFieldDefaultsAcrossModules
import Box from "./data.ms"
import expect_true, fail from "@std/test.ms"

test "imported constructor retains default module and generic scope":
    let box = Box(value: "text")
    if box.copied != "text" or box.items.get(0) != "text":
        return fail("imported generic defaults")
