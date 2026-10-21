type Box:
    items: List[Int]

impl Box:
    fn list() List[Int]:
        return self.items

fn f(b: Box) Int:
    var xs = b.list()  # error: cannot borrow mutably
    xs.append(1)
    return xs.length()
