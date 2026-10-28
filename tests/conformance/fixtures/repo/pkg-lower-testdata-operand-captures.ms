# conform: tags=control-flow,faults,lists,match,modules,mutation,optional,records,stdlib-faults,testing,tier-stdlib
# conform: phase=test
# conform: origin=pkg/lower/testdata/operand-captures.ms
import panic from "@std/core.ms"

type Counter:
    value: Int

fn advance(var counter: Counter) Int:
    counter.value += 1
    return counter.value

fn mixed(var counter: Counter) List[Int]:
    var value = 1
    return [
        value,
        counter.value,
        counter.value,
        advance(var counter),
        value,
        match some(2):
            some(number):
                value = number
                advance(var counter)
            none: 0
        ,
        value,
        counter.value,
        advance(var counter)
    ]

test "multiple captures survive later statement growth":
    var counter = Counter(0)
    if mixed(var counter) != [1, 0, 0, 1, 1, 2, 2, 2, 3]:
        return panic("operand evaluation order changed")
    if counter.value != 3: return panic("effect count changed")

test "pending captures grow beyond the small buffer":
    var counter = Counter(0)
    let values = [
        counter.value, counter.value, counter.value, counter.value, counter.value,
        counter.value, counter.value, counter.value, counter.value, advance(var counter)
    ]
    if values != [0, 0, 0, 0, 0, 0, 0, 0, 0, 1]:
        return panic("earlier field reads changed")

    var copy = counter.clone()
    let separate = [copy.value, advance(var copy), copy.value]
    if separate != [1, 2, 2]: return panic("copy lost its own mutations")
    if counter.value != 1: return panic("copy changed the original")
