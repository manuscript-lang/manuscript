# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:367 TestFormatExpressionLayouts
from "./contracts.ms" import First, Second, Third, Fourth, Fifth

def work(first: Int, second: Int, third: Int, fourth: Int) -> Int: return first
