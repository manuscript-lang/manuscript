# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_test.go:44 TestFormatImplicitReturnPreservesOperands
fn sum(first_value: Int, second_value: Int, third_value: Int, fourth_value: Int) Int: first_value + second_value + third_value + fourth_value
