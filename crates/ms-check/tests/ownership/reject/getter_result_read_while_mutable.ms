type Box:
    items: List[Int]

impl Box:
    fn list() List[Int]:
        return self.items

fn f(var b: Box) Int:
    var xs = b.list()
    let n = b.items.length()  # error: cannot use `b.items` while `xs`
    xs.append(n)
    return n
