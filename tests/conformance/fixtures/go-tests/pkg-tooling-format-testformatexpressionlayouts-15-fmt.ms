# conform: tags=aliasing,closures,control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:142 TestFormatExpressionLayouts
fn work() Int:
    if let value = [2, 5, 3, (-6), (-9), 1, 2, 3, 4].clone().sorted(fn(l: Int, r: Int) Int: l - r).first():
        return value
    return 0
