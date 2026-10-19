# conform: tags=formatter,match,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/control-flow/pattern-matching.md:83
fn paid(payment: Payment) Bool:
    match payment:
        Paid(_):
            return true
        _:
            return false
