type Bag:
    items: List[Int]

fn push(var xs: List[Int]) Void:
    xs.append(1)

fn main() Void:
    var a: List[Int] = []
    var bag = Bag(items: [])
    push(var a)
    push(var bag.items)
    push(a)
    push(bag.items)
