# conform: tags=diagnostics,interpolation,match,strings,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/control-flow/pattern-matching.md:12
fn describe(payment: Payment) String:
    match payment:
        Paid(receipt):
            return "Paid: {receipt}"
        Declined(reason):
            return "Declined: {reason}"
        Pending(reference):
            return "Pending: {reference}"
