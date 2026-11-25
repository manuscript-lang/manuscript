// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/format/format_layout_test.go:367 TestFormatExpressionLayouts
import Fifth, First, Fourth, Second, Third from "./contracts.ms"

fn work(first Int, second Int, third Int, fourth Int) Int => return first
// expect-error: MS2002 4:1 cannot find module ./contracts.ms (looked for contracts.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
