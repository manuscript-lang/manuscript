// conform: tags=diagnostics
// conform: phase=check
test %q:
    minimum := nanoseconds(-9223372036854775808)
    maximum := nanoseconds(9223372036854775807)
    divide := minimum.divide
