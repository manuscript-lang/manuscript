type Big:
    name: String
    items: List[Int]

fn items_of(b: Big) List[Int]:
    return b.items

fn both(b: Big) Int:
    let n = size(b.items)
    return n.length() + b.name.length()

fn size(xs: List[Int]) List[Int]:
    return xs

fn branch(b: Big, flag: Bool) Int:
    if flag:
        let ys = size(b.items)
        return ys.length()
    return b.items.length() + b.name.length()

fn reinit(b: Big) Int:
    var c = b
    let first = size(c.items)
    c.items = [first.length()]
    return c.items.length()

fn nested(w: Wrap) List[Int]:
    return w.inner.items

type Wrap:
    inner: Big
    tag: Int

type Cell:
    items: List[Int]

type Holder:
    inner: Cell

fn paths(b: Cell, first: Bool) List[Int]:
    if first:
        return b.items

    let w = Holder(inner: b)
    return w.inner.items.clone()
