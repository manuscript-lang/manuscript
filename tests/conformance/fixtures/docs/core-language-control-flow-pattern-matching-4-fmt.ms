# conform: tags=formatter,match,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/control-flow/pattern-matching.md:83
def paid(payment: Payment) -> Bool:
    match payment:
        case Paid(_):
            return True
        case _:
            return False
