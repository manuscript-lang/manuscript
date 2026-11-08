type Bag:
    items: List[Int]

impl Bag:
    fn view() List[Int]: self.items

fn go(bag: Bag) Unit:
    bag.view().append(2)  // error: cannot change the result of
    bag.view()[0] = 1  // error: cannot change the result of
