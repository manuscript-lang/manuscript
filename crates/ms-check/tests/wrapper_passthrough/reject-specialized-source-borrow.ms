type Box:
    items: List[Int]

fn Box.read[T](_tag: T) List[Int]: self.items

fn var Box.change[T](_tag: T) Int:
    self.items.append(3)
    return self.items.length()

fn bad() Int:
    var box = Box([1, 2])
    view := box.read[Int](0)
    box.change[Int](0)
    return view.length()
