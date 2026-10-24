type Box:
    items: List[Int]

impl Box:
    fn list() ref List[Int]:
        return self.items

fn f(var b: Box) Int:
    var x = b.list()
    var y = b.list()  # error: cannot borrow mutably
    x.append(1)
    return y.length()
