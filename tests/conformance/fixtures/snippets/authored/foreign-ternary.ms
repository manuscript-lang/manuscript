# conform: tags=diagnostics,parser,tier-core
# conform: phase=parse
# conform: origin=foreign-syntax diagnostics
fn f(x: Int) Int:
    return 1 if x > 0 else 2
