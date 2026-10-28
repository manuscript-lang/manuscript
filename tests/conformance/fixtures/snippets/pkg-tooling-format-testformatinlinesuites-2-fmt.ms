# conform: tags=control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_test.go:179 TestFormatInlineSuites
fn double(x: Int) Int: return x * 2

fn f(x: Int) Int:
    if x > 0: return double(x)
    else: return 0
