# conform: tags=diagnostics,maps,optional,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:380 TestFormatExpressionLayouts
def work(
    first: Int,
    second: String
) -> Result[Optional[Map[String, String]], ApplicationError]:
    return error(cause)
