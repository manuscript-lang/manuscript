type Cursor:
    items: ref List[Int]
    at: Int

fn first(c: Cursor) Int:
    return c.items[c.at]

export fn main() Int:
    var xs = [1, 2]
    let c = Cursor(items: xs, at: 0)
    return first(c)
