type Box:
    name: String
    items: List[Int]

impl Box:
    fn list() ref List[Int]:
        return self.items

    fn pick(first: Bool) ref List[Int]:
        if first:
            return self.items

        return [1]

fn borrow_it(var b: Box) Int:
    var xs = b.list()
    xs.append(1)
    return b.items.length()

fn copy_it(var b: Box) Int:
    var xs = b.pick(true).clone()
    xs.append(1)
    return b.items.length()
