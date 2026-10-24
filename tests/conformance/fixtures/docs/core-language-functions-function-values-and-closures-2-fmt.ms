# conform: tags=closures,formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/functions/function-values-and-closures.md:27
def subtract_one(amount: Int) -> Int:
    return amount - 1

def adapt() -> Unit:
    # Rejected: amount and value are different function-type labels.
    let invalid: Callable[[Int], Int] = subtract_one
    let renamed = lambda (value: Int) -> Int:
        return subtract_one(amount: value)
    let result = apply(value: 3, transform: renamed)
