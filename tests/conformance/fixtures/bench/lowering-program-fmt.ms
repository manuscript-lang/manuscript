# conform: tags=control-flow,faults,formatter,lists,modules,mutation,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=bench/lowering/program.ms

fn scalar(limit: Int) Int:
    var total = 0
    for index in 0..limit:
        total += index
    return total

fn add(left: Int, right: Int) Int: left + right

fn calls(limit: Int) Int:
    var total = 0
    for index in 0..limit:
        total = add(total, index)
    return total

fn items(values: List[Int], limit: Int) Int:
    var total = 0
    for index in 0..limit:
        total += values.get(index)
    return total
