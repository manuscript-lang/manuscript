import expect_equal, expect_true from "@std/test.ms"

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

fn either(a: Shelf, b: Shelf, flag: Bool) ref List[String]:
    if flag:
        return a.names

    return b.names

fn stocked(h: Holder) ref Shelf?:
    match h.item:
        Stocked(shelf): return shelf
        Plain: return none

fn first_stocked(h: Holder) ref Shelf?:
    match h.items[0]:
        Stocked(shelf): return shelf
        Plain: return none

fn last_name(h: Holder) ref String:
    for name in h.racks[0].names:
        if name.starts_with("g"):
            return name
    return h.racks[0].names[0]

fn chosen(a: Shelf, b: Shelf) ref String:
    for name in either(a, b, false):
        return name
    return a.names[0]

fn chosen_let(a: Shelf, b: Shelf) ref String:
    let names = either(a, b, true)
    for name in names:
        return name
    return a.names[0]

fn chosen_list(a: Shelf, b: Shelf) ref List[String]:
    let names = either(a, b, false)
    return names

fn first_name(s: Shelf) ref String?:
    let name = s.names.first()
    return name

fn last_of(s: Shelf) ref String?:
    return s.names.last()

fn age(s: Shelf, key: String) ref String?:
    let found = s.ages.get(key)
    return found

fn shelf(names: List[String]) Shelf:
    return Shelf(names: names, ages: {"ada": "36"})

fn holder() Holder:
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
    try expect_equal(first_name(b), "grace")
    try expect_equal(last_of(b), "hopper")
    try expect_true(first_name(shelf([])).is_none())
    try expect_true(last_of(shelf([])).is_none())
    try expect_equal(age(a, "ada"), "36")
    try expect_true(age(a, "grace").is_none())

fn find(items: List[Shelf], first: String) ref Shelf?:
    for s in items:
        if s.names[0] == first:
            return s
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
