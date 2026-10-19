# conform: tags=aliasing,control-flow,formatter,modules,mutation,parser,stdlib-string,strings,tier-stdlib
# conform: phase=parse
# conform: origin=tests/e2e/builder_range_test.go:180 TestBuilderAndRangeFaultFrames
import StringBuilder from "@std/string.ms"
fn probe() String:
    let b = StringBuilder()
    var i = 0
    while i < 321:
        b.append("x")
        i += 1
    return b.freeze()
