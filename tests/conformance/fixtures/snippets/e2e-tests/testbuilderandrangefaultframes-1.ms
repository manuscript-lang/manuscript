// conform: tags=control-flow,diagnostics,modules,mutation,stdlib-string,strings,tier-stdlib
// conform: phase=check
// conform: origin=tests/e2e/builder_range_test.go:180 TestBuilderAndRangeFaultFrames

fn probe() String:
    var b = ""
    var i = 0

    while i < 321:
        b += "x"
        i += 1

    return b
