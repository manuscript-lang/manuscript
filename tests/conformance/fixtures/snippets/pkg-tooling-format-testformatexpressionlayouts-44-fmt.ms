# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:330 TestFormatExpressionLayouts
def work() -> Bool:
    return (
        account_is_active
        and payment_is_allowed
        and remaining_balance > minimum_balance
    )
