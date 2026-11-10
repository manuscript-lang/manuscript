type Bag[T]:
    items: List[T]

impl Bag[T]:
    fn at(index: Int) T?:
        if index < 0 or index >= self.items.length(): return none

        return self.items.get(index)

fn nth[T](xs: List[T], index: Int) T?:
    return xs.get(index)

export fn main() Int:
    let bag = Bag(items: [1, 2, 3])
    return bag.at(1).get(0) + nth([4, 5], 0).get(0)
