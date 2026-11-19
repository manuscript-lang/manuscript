interface Sink:
    var fn push(x: Int) Void

type Items:
    xs: List[Int]

fn var Items.push(x: Int) Void: self.xs.append(x)

fn fill(var s: Sink) Void:
    s.push(1)

fn main() Int:
    var items = Items(List[Int]())
    fill(items)  // error: would be converted to a temporary Sink
    return items.xs.length()
