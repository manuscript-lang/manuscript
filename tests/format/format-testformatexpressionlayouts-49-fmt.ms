// conform: tags=formatter,modules,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/format/format_layout_test.go:367 TestFormatExpressionLayouts
import Fifth, First, Fourth, Second, Third from "./contracts.ms"

fn work(first Int, second Int, third Int, fourth Int) Int => return first
// expect-format: rewritten
// expect-formatted: import Fifth, First, Fourth, Second, Third from "./contracts.ms"
// expect-formatted:
// expect-formatted: fn work(first, second, third, fourth Int) Int => return first
