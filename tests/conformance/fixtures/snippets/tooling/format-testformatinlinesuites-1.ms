# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_test.go:174 TestFormatInlineSuites
fn double(x: Int) Int: return x * 2

fn f(x: Int) Int:
    if x > 0: return double(x)
    else: return 0
