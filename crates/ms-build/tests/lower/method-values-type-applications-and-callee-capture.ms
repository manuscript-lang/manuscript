# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "closure.new"

from "@std/io.ms" import stdout

def identity[T](value: T) -> T: value

def run(f: Callable[[Int], Int]) -> Int: f(1)

export def main() -> Int:
    let items = [4, 5]
    let count = items.count
    let lookup = items.get
    let same = identity[Int]
    var selected = identity[Int]
    let n = selected(match some(0):
        case some(_):
            selected = lambda (value: Int): value + 1
            3
        case none: 3
    )
    let _r = stdout().write(f"{lookup(1)} {n} {run(same)} {count(lambda (x: Int): x > 4)}\n")
    return 0
