from "@std/testing.ms" import expect_equal, expect_true

type Shelf:
    names: List[String]
    ages: Map[String, String]
    spare: List[String]

type Item:
    case Plain
    case Named(text: String, tags: List[String])

impl Shelf:
    def pick(flag: Bool) -> ref List[String]:
        if flag:
            return self.names

        return self.spare

    def age(name: String) -> ref Optional[String]:
        if name == "":
            return none

        return self.ages.get(name)

    def name(index: Int) -> ref Optional[String]:
        if index < 0 or index >= self.names.length():
            return none

        return some(self.names.get(index))

impl Item:
    def text() -> ref Optional[String]:
        match self:
            case Named(text, _): return some(text)
            case _: return none

    def tags() -> ref Optional[List[String]]:
        match self:
            case Named(_, tags): return some(tags)
            case _: return none

interface Names:
    def names() -> ref List[String]

impl Names for Shelf:
    def names() -> ref List[String]:
        return self.names

type Holder:
    inner: Shelf
    source: Names

impl Holder:
    # Lends through another user `ref` function.
    def shelved() -> ref List[String]:
        return self.inner.pick(True)

    # A `ref` interface operation lends, so this one is handed back too.
    def listed() -> ref List[String]:
        return self.source.names()

    def maybe(flag: Bool) -> ref Optional[List[String]]:
        if flag:
            return some(self.inner.names)

        return none

# The second argument is a temporary freed at return, so the result is an owned copy and the
# function cannot be `ref`.
def either(a: Shelf, b: Shelf, flag: Bool) -> ref List[String]:
    if flag:
        return a.names

    return b.names

def from_temporary(s: Shelf) -> List[String]:
    return either(s, Shelf(names: ["temporary"], ages: {}, spare: []), False)

def shelf() -> Shelf:
    return Shelf(names: ["ada", "grace"], ages: {"ada": "36"}, spare: ["x"])

test "ref functions hand back the argument's own storage":
    let s = shelf()
    try expect_equal(s.pick(True).length(), 2)
    try expect_equal(s.pick(False).length(), 1)
    try expect_equal(s.pick(True), ["ada", "grace"])

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
    if let names = h.maybe(True):
        try expect_equal(names.length(), 2)
    try expect_true(h.maybe(False).is_none())
    try expect_equal(h.shelved(), ["ada", "grace"])

test "a result over a temporary argument is an owned copy":
    let s = shelf()
    try expect_equal(from_temporary(s), ["temporary"])

test "a method value of a ref operation returns an owned copy":
    let n: Names = Shelf(names: ["ada", "grace"], ages: {}, spare: [])
    let names = n.names
    let copy = names()
    try expect_equal(copy, ["ada", "grace"])
