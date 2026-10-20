# conform: tags=closures,control-flow,faults,formatter,lists,modules,mutation,parser,records,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=bench/lists/program.ms
import range from "@std/collections.ms"

fn build(count: Int) List[Int]:
    var values: List[Int] = []
    for i in range(0, count):
        values.append(i * 7919 % 100003)
    return values

fn index(values: List[Int], count: Int) Int:
    var total = 0
    for i in range(0, count):
        total += values.get(i % values.length())
    return total

fn iterate(values: List[Int]) Int:
    var total = 0
    for value in values:
        total += value
    return total

type Total:
    value: Int

fn callbacks(values: List[Int]) Int:
    var total = Total(0)
    values.for_each(
        fn(value):
            total.value += value
    )
    return total.value

fn sorted(values: List[Int]) List[Int]:
    return values.sorted(compare)

fn compare(left: Int, right: Int) Int:
    if left < right: return -1
    if left > right: return 1

    return 0

export fn main() Int: return 0

fn callback_write(var values: List[Int]) Int:
    var total = Total(0)
    (
        values.clone().for_each(
            fn(value):
                total.value += value
                if value == 0:
                    values.set(0, 7)
        )
    )
    return total.value
