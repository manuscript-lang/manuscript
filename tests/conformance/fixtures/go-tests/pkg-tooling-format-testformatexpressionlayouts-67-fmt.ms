# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:487 TestFormatExpressionLayouts
fn work() Bool:
    return Error(value: CommandError.Failed(message: "command diagnostic")).message() != "command diagnostic"
