// conform: tags=control-flow,formatter,lists,mutation,parser,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/functions/declarations-and-calls.md:86
fn sum(values: List[Int]) Int:
    var total = 0
    for value in values:
        total += value
    return total

total := sum([1, 2, 3])
empty := sum([])
