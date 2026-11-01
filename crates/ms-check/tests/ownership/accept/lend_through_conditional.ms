type Row:
    name: String
    tags: List[String]

type Table:
    rows: List[Row]

type Shape:
    case Circle(label: String)
    case Rect(label: String, w: Int)

impl Table:
    fn head() Row:
        return self.rows[0]

    # A field or element of a lending call's result is a part of the same source.
    fn first_tag() String:
        return self.head().tags[0]

    fn head_name() String:
        return self.head().name

impl Shape:
    # Every arm of a returned match lends: the function lends.
    fn label() String:
        return match self:
            Circle(label): label
            Rect(label, _w): label

fn label(r: Row) String:
    return r.name

fn pick(a: Row, b: Row, flag: Bool) String:
    return if flag: a.name else: b.name

# A binding of a conditional whose arms all lend borrows every source.
fn pick_bound(a: Row, b: Row, flag: Bool) String:
    let x = if flag: label(a) else: label(b)
    return x

fn use(t: Table, a: Row, b: Row, s: Shape) Int:
    let w = if a.name == "a": label(a) else: label(b)
    let n = t.first_tag().length() + t.head_name().length() + pick(a, b, true).length()
    return n + pick_bound(a, b, false).length() + s.label().length() + w.length()
