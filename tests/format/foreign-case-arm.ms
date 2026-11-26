// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
enum E {
    A
}

fn f(e E) Int {
    match e {
        case A: return 1
    }
}
// expect-error: MS1000 10:9-10:14 match arms use bare variant names, e.g. Paid(receipt) => value or Missing => value; remove the legacy 'case' prefix
// expect-fix: 10:9-10:14 ""
// expect-format-exit: 1
