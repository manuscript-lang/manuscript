# conform: tags=control-flow,diagnostics,lists,mutation,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/control-flow/loops.md:12
def sum(values: List[Int]) -> Int:
    var total = 0
    for value in values:
        total += value
    return total
