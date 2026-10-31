import expect_equal, expect_true from "@std/test.ms"

type Shelf:
    names: List[String]
    ages: Map[String, String]
    spare: List[String]

type Item:
    case Plain
    case Named(text: String, tags: List[String])

impl Shelf:
    fn pick(flag: Bool) ref List[String]:
        if flag:
            return self.names

        return self.spare

    fn age(name: String) String?:
        if name == "":
            return none

        return self.ages.get(name)

    fn name(index: Int) String?:
        if index < 0 or index >= self.names.length():
            return none

        return self.names.get(index)

impl Item:
    fn text() ref String?:
        match self:
            Named(text, _): return text
            _: return none

    fn tags() ref List[String]?:
        match self:
            Named(_, tags): return tags
            _: return none

interface Names:
    fn names() ref List[String]

impl Names for Shelf:
    fn names() ref List[String]:
        return self.names

type Holder:
    inner: Shelf
    source: Names

impl Holder:
    # Lends through another user `ref` function.
    fn shelved() ref List[String]:
        return self.inner.pick(true)

    # A `ref` interface operation lends, so this one is handed back too.
    fn listed() ref List[String]:
        return self.source.names()

    fn maybe(flag: Bool) ref List[String]?:
        if flag:
            return self.inner.names

        return none

# The second argument is a temporary freed at return, so the result is an owned copy and the
# function cannot be `ref`.
fn either(a: Shelf, b: Shelf, flag: Bool) ref List[String]:
    if flag:
        return a.names

    return b.names

fn from_temporary(s: Shelf) List[String]:
    return either(s, Shelf(names: ["temporary"], ages: {}, spare: []), false)

fn shelf() Shelf:
    return Shelf(names: ["ada", "grace"], ages: {"ada": "36"}, spare: ["x"])

test "ref functions hand back the argument's own storage":
    let s = shelf()
    try expect_equal(s.pick(true).length(), 2)
    try expect_equal(s.pick(false).length(), 1)
    try expect_equal(s.pick(true), ["ada", "grace"])

test "ref Optional results borrow map entries and list elements":
    let s = shelf()
    if let age = s.age("ada"):
        try expect_equal(age, "36")
    try expect_true(s.age("grace").is_none())
    try expect_true(s.age("").is_none())
    if let name = s.name(1):
        try expect_equal(name, "grace")
    try expect_true(s.name(2).is_none())
    try expect_true(s.name(-1).is_none())

test "ref Optional results borrow alternative payloads":
    let item = Item.Named("title", ["a", "b"])
    if let text = item.text():
        try expect_equal(text, "title")
    if let tags = item.tags():
        try expect_equal(tags.length(), 2)
    try expect_true(Item.Plain.text().is_none())
    try expect_true(Item.Plain.tags().is_none())

    # The receiver is unchanged after reading through the borrow.
    try expect_equal(item, Item.Named("title", ["a", "b"]))

test "user ref functions chain borrows and copy interface results":
    let h = Holder(inner: shelf(), source: shelf())
    try expect_equal(h.shelved(), ["ada", "grace"])
    try expect_equal(h.listed(), ["ada", "grace"])
    if let names = h.maybe(true):
        try expect_equal(names.length(), 2)
    try expect_true(h.maybe(false).is_none())
    try expect_equal(h.shelved(), ["ada", "grace"])

test "a result over a temporary argument is an owned copy":
    let s = shelf()
    try expect_equal(from_temporary(s), ["temporary"])

test "a method value of a ref operation returns an owned copy":
    let n: Names = Shelf(names: ["ada", "grace"], ages: {}, spare: [])
    let names = n.names
    let copy = names()
    try expect_equal(copy, ["ada", "grace"])
