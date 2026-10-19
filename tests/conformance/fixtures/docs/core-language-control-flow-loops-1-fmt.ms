# conform: tags=control-flow,formatter,lists,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/control-flow/loops.md:12
fn sum(values: List[Int]) Int:
    var total = 0
    for value in values:
        total += value

    return total
