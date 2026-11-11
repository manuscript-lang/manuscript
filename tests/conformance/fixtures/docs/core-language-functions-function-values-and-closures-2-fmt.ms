// conform: tags=closures,formatter,parser,records,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/functions/function-values-and-closures.md:27
fn subtract_one(amount: Int) Int:
    return amount - 1

fn adapt() Unit:
    // Rejected: amount and value are different function-type labels.
    invalid: fn(Int) Int := subtract_one
    renamed := fn(value: Int) Int:
        return subtract_one(amount: value)
    result := apply(value: 3, transform: renamed)
