type Bag:
    items: List[Int]

fn Bag.view() List[Int]: self.items

fn same(bag: Bag) Bag:
    return bag

fn go(bag: Bag) Unit:
    bag.view().append(2)  // error: cannot change the result of
    bag.view()[0] = 1  // error: cannot change the result of
    same(bag).items.append(3)  // error: cannot change the result of
    same(bag).items[0] = 4  // error: cannot change the result of
