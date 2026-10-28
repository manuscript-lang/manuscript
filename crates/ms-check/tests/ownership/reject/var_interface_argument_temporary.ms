interface Sink:
    var def push(x: Int) -> Unit

type Items:
    xs: List[Int]

impl Sink for Items:
    var def push(x: Int) -> Unit: self.xs.append(x)

def fill(var s: Sink) -> Unit:
    s.push(1)

def main() -> Int:
    var items = Items(List[Int]())
    fill(var items)  # error: would be converted to a temporary Sink
    return items.xs.length()
