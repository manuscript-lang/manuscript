type Item:
    name: String

type Count:
    value: Int

enum Flag:
    off
    on

enum Number:
    value(n: Int)

fn inputs(
    a: Int8,
    b: Int16,
    c: Int32,
    d: Int64,
    e: Float32,
    f: Float,
    g: Int,
    h: Bool,
    i: Unit,
    j: Flag,
    k: Number,
    item: Item,
    count: Count,
    var changed: Int
) Unit:
    return unit

fn item_name(item: Item) String:
    return item.name

fn fresh_name(item: Item) String:
    return item.name + "!"

fn generic[T](value: T) T:
    return value

fn hold(item: Item) List[Item]:
    return [item]

fn optional_name(item: Item) String?:
    return item.name

fn result_name(item: Item) String!:
    return ok(item.name)

fn maybe_name(item: Item, found: Bool) String!:
    if found: return ok(item.name)

    return error(Error("missing"))

fn either(item: Item, issue: Error, failed: Bool) String!:
    if failed: return error(issue)

    return ok(item.name)

fn mixed_both(item: Item, issue: Error, mode: Int) String!:
    if mode == 0: return ok(item.name)
    if mode == 1: return error(issue)
    if mode == 2: return ok("fresh")

    return error(Error("missing"))

interface Named:
    fn name() String

impl Named for Item:
    fn name() String:
        return self.name.clone()

impl Item:
    fn borrowed() String:
        return self.name

    fn copied(value: Int8) Int8:
        return value

    fn boxed(item: Item) List[Item]:
        return [item]

fn named(item: Item) Named:
    return item

fn maybe_count(issue: Error, failed: Bool) Int!:
    if failed: return error(issue)

    return ok(1)

extern fn ms_ownership_scalar(value: Int8) Int8
