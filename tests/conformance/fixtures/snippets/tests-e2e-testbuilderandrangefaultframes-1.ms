# conform: tags=control-flow,diagnostics,modules,mutation,stdlib-string,strings,tier-stdlib
# conform: phase=check
# conform: origin=tests/e2e/builder_range_test.go:180 TestBuilderAndRangeFaultFrames
from "@std/string.ms" import StringBuilder

def probe() -> String:
    var b = StringBuilder()
    var i = 0

    while i < 321:
        b.append("x")
        i += 1

    return b.freeze()
