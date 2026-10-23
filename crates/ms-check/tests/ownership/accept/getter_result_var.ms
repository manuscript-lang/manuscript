type Box:
    name: String
    items: List[Int]

impl Box:
    fn list() List[Int]:
        return self.items

    fn pick(first: Bool) List[Int]:
        if first:
            return self.items

        return [1]

fn borrow_it(var b: Box) Int:
    var xs = b.list()
    xs.append(1)
    return b.items.length()

fn copy_it(var b: Box) Int:
    var xs = b.pick(true)
    xs.append(1)
    return b.items.length()
