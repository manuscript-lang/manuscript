type Box:
    items: List[Int]

impl Box:
    var fn change[T](_tag: T) Int:
        self.items.append(3)
        return self.items.length()

fn observe(items: List[Int], changed: Int) Int: items.length() + changed

fn bad() Int:
    var box = Box([1, 2])
    return observe(box.items, box.change[Int](0))
