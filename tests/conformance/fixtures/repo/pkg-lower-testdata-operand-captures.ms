# conform: tags=control-flow,faults,lists,match,modules,mutation,optional,records,stdlib-faults,testing,tier-stdlib
# conform: phase=test
# conform: origin=pkg/lower/testdata/operand-captures.ms
import panic from "@std/faults.ms"

type Counter:
    value: Int

fn advance(counter: Counter) Int:
    counter.value += 1
    return counter.value

fn mixed(counter: Counter) List[Int]:
    var value = 1
    return [
        value,
        counter.value,
        counter.value,
        advance(counter),
        value,
        match some(2):
            some(number):
                value = number
                advance(counter)
            none: 0
        ,
        value,
        counter.value,
        advance(counter)
    ]

test "multiple captures survive later statement growth":
    let counter = Counter(0)
    if mixed(counter) != [1, 0, 0, 1, 1, 2, 2, 2, 3]:
        return panic("operand evaluation order changed")
    if counter.value != 3: return panic("effect count changed")

test "pending captures grow beyond the small buffer":
    let counter = Counter(0)
    let values = [
        counter.value,
        counter.value,
        counter.value,
        counter.value,
        counter.value,
        counter.value,
        counter.value,
        counter.value,
        counter.value,
        advance(counter)
    ]
    if values != [0, 0, 0, 0, 0, 0, 0, 0, 0, 1]:
        return panic("earlier field reads changed")

    let alias = counter
    let shared = [alias.value, advance(alias), alias.value]
    if shared != [1, 2, 2]: return panic("immutable alias lost shared mutations")
    if counter.value != 2: return panic("aliased effect count changed")
