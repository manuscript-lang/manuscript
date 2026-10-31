# conform: tags=control-flow,diagnostics,maps,mutation,strings,tier-core,try-result
# conform: phase=check
# conform: origin=documentation/core-language/control-flow/loops.md:89
fn total(values: Map[String, Int]) Int:
    var sum = 0

    for entry in values:
        let {key: _key, value} = entry
        sum += value

    return sum
