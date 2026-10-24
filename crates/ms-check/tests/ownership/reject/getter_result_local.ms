type Box:
    items: List[Int]

impl Box:
    fn list() ref List[Int]:
        return self.items

fn f() List[Int]:
    let b = Box(items: [1])
    return b.list()  # error: only a read-only parameter can
