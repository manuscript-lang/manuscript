from "@std/testing.ms" import expect_equal, expect_true

# Each lending function here hands back a part reached through a match, a loop or a `let`.
# Lowering must read those parts in place: a copy would be freed before the caller reads it.
type Shelf:
    names: List[String]
    ages: Map[String, String]

type Item:
    case Plain
    case Stocked(shelf: Shelf)

type Holder:
    item: Item
    items: List[Item]
    racks: List[Shelf]

def either(a: Shelf, b: Shelf, flag: Bool) -> ref List[String]:
    if flag:
        return a.names

    return b.names

def stocked(h: Holder) -> ref Optional[Shelf]:
    match h.item:
        case Stocked(shelf): return some(shelf)
        case Plain: return none

def first_stocked(h: Holder) -> ref Optional[Shelf]:
    match h.items[0]:
        case Stocked(shelf): return some(shelf)
        case Plain: return none

def last_name(h: Holder) -> ref String:
    for name in h.racks[0].names:
        if name.starts_with("g"):
            return name
    return h.racks[0].names[0]

def chosen(a: Shelf, b: Shelf) -> ref String:
    for name in either(a, b, False):
        return name
    return a.names[0]

def chosen_let(a: Shelf, b: Shelf) -> ref String:
    let names = either(a, b, True)
    for name in names:
        return name
    return a.names[0]

def chosen_list(a: Shelf, b: Shelf) -> ref List[String]:
    let names = either(a, b, False)
    return names

def first_name(s: Shelf) -> ref Optional[String]:
    let name = s.names.first()
    return name

def last_of(s: Shelf) -> ref Optional[String]:
    return s.names.last()

def age(s: Shelf, key: String) -> ref Optional[String]:
    let found = s.ages.get(key)
    return found

def shelf(names: List[String]) -> Shelf:
    return Shelf(names: names, ages: {"ada": "36"})

def holder() -> Holder:
    let s = shelf(["ada", "grace"])
    return Holder(
        item: Item.Stocked(s.clone()), items: [Item.Stocked(s.clone()), Item.Plain],
        racks: [s]
    )

test "match payloads of a parameter's parts are lent":
    let h = holder()
    if let s = stocked(h):
        try expect_equal(s.names, ["ada", "grace"])
    if let s = first_stocked(h):
        try expect_equal(s.names.length(), 2)

    let plain = Holder(item: Item.Plain, items: [Item.Plain], racks: [])
    try expect_true(stocked(plain).is_none())
    try expect_true(first_stocked(plain).is_none())

test "loop variables over a parameter's parts are lent":
    let h = holder()
    try expect_equal(last_name(h), "grace")

    let a = shelf(["ada"])
    let b = shelf(["grace", "hopper"])
    try expect_equal(chosen(a, b), "grace")
    try expect_equal(chosen_let(a, b), "ada")

test "let bindings of lending calls and accessors are lent":
    let a = shelf(["ada"])
    let b = shelf(["grace", "hopper"])
    try expect_equal(chosen_list(a, b), ["grace", "hopper"])
    try expect_equal(first_name(b), some("grace"))
    try expect_equal(last_of(b), some("hopper"))
    try expect_true(first_name(shelf([])).is_none())
    try expect_true(last_of(shelf([])).is_none())
    try expect_equal(age(a, "ada"), some("36"))
    try expect_true(age(a, "grace").is_none())

def find(items: List[Shelf], first: String) -> ref Optional[Shelf]:
    for s in items:
        if s.names[0] == first:
            return some(s)
    return none

test "a lent result keeps its argument alive after the argument's last use":
    let items = [shelf(["ada lovelace", "and more"]), shelf(["grace hopper"])]

    # `items` is not used again, so its drop could move up to the call.
    if let s = find(items, "ada lovelace"):
        try expect_equal(s.names[1], "and more")

test "an owned temporary in an argument that is not lent from":
    let s = shelf(["ada", "grace"])
    let racks = [s.clone()]
    let h = Holder(item: Item.Plain, items: [], racks: racks)
    if let found = find(h.racks, "ad" + "a"):
        try expect_equal(found.names, ["ada", "grace"])
