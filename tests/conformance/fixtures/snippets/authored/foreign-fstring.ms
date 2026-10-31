# conform: tags=diagnostics,parser,tier-core
# conform: phase=parse
# conform: origin=foreign-syntax diagnostics
fn f() String:
    let n = 1
    return f"n={n}"
