# conform: tags=control-flow,diagnostics,lists,mutation,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/functions/declarations-and-calls.md:86
fn sum(values: List[Int]) Int:
    var total = 0
    for value in values:
        total += value
    return total

let total = sum([1, 2, 3])
let empty = sum([])
