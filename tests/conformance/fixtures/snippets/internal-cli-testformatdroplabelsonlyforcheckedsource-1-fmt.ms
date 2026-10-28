# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=internal/cli/cli_test.go:449 TestFormatDropLabelsOnlyForCheckedSource
fn add(left: Int, right: Int) Int: left + right

fn total(left: Int, right: Int) Int:
    return add(left: left, right: right)
