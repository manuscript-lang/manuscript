# conform: tags=formatter,interpolation,match,parser,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/control-flow/pattern-matching.md:12
def describe(payment: Payment) -> String:
    match payment:
        case Paid(receipt):
            return f"Paid: {receipt}"
        case Declined(reason):
            return f"Declined: {reason}"
        case Pending(reference):
            return f"Pending: {reference}"
