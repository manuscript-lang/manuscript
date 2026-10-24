# conform: tags=control-flow,formatter,lists,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/functions/declarations-and-calls.md:86
def sum(values: List[Int]) -> Int:
    var total = 0
    for value in values:
        total += value
    return total

let total = sum([1, 2, 3])
let empty = sum([])
