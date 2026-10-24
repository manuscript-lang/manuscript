# conform: tags=control-flow,diagnostics,faults,modules,stdlib-testing,testing,tier-core
# conform: phase=check
# conform: origin=tests/e2e/e2e_test.go:547 TestFieldDefaultsAcrossModules
from "./data.ms" import Box
from "@std/testing.ms" import expect_true, fail

test "imported constructor retains default module and generic scope":
    let box = Box(value: "text")
    if box.copied != "text" or box.items.get(0) != "text":
        return fail("imported generic defaults")
