type Box:
    items: List[Int]

impl Box:
    fn read[T](_tag: T) List[Int]: self.items

    var fn change[T](_tag: T) Int:
        self.items.append(3)
        return self.items.length()

fn bad() Int:
    var box = Box([1, 2])
    let view = box.read[Int](0)
    box.change[Int](0)
    return view.length()
