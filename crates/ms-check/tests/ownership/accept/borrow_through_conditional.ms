type Row:
    name: String
    tags: List[String]

type Table:
    rows: List[Row]

enum Shape:
    Circle(label: String)
    Rect(label: String, w: Int)

fn Table.head() Row:
    return self.rows[0]

// A field or element of a borrow-returning call's result is a part of the same source.
fn Table.first_tag() String:
    return self.head().tags[0]

fn Table.head_name() String:
    return self.head().name

// Every arm of a returned match returns a borrow: so does the function.
fn Shape.label() String:
    return match self:
        Circle(label): label
        Rect(label, _w): label

fn label(r: Row) String:
    return r.name

fn pick(a: Row, b: Row, flag: Bool) String:
    return if flag: a.name else: b.name

// A binding of a conditional whose arms all return a borrow, so it borrows every source.
fn pick_bound(a: Row, b: Row, flag: Bool) String:
    x := if flag: label(a) else: label(b)
    return x

fn use(t: Table, a: Row, b: Row, s: Shape) Int:
    w := if a.name == "a": label(a) else: label(b)
    n := t.first_tag().length() + t.head_name().length() + pick(a, b, true).length()
    return n + pick_bound(a, b, false).length() + s.label().length() + w.length()
