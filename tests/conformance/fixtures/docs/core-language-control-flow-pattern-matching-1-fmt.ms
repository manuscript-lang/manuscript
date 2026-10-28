# conform: tags=formatter,interpolation,match,parser,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/control-flow/pattern-matching.md:12
fn describe(payment: Payment) String:
    match payment:
        Paid(receipt):
            return "Paid: {receipt}"
        Declined(reason):
            return "Declined: {reason}"
        Pending(reference):
            return "Pending: {reference}"
