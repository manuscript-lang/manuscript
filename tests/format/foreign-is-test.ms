// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f(x Int) Bool => x is Int
// expect-error: MS1000 4:23-4:25 expected end of expression, found name 'is'; '=>' takes one expression; for more statements, write the body in braces; there is no 'is' operator: write '==' to compare values, or 'match value { ... }' to test which alternative a value is
// expect-format-exit: 1
