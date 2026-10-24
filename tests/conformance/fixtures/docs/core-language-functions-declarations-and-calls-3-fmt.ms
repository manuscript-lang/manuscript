# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/functions/declarations-and-calls.md:61
def subtract(amount: Int, deduction: Int = 1) -> Int:
    return amount - deduction

def example() -> Int:
    let usual = subtract(5)
    let explicit = subtract(5, 2)
    return usual + explicit
