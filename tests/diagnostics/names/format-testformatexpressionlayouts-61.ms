// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/format/format_layout_test.go:448 TestFormatExpressionLayouts
fn work(value Bool = active and allowed and remaining > 0) Bool => return value
// expect-error: MS2001 4:22 unknown binding active; declare it with 'active := ...' before use, define 'fn active(...) T { ... }', or import it from a module
// expect-error: MS2001 4:33 unknown binding allowed; declare it with 'allowed := ...' before use, define 'fn allowed(...) T { ... }', or import it from a module
// expect-error: MS2001 4:45 unknown binding remaining; declare it with 'remaining := ...' before use, define 'fn remaining(...) T { ... }', or import it from a module
