type Key:
    id: Int

// ms: allow_effect std.console.write
fn Key.equals(other: Key) Bool:
    print("equals")
    return self.id == other.id

// ms: allow_effect std.console.write
fn Key.hash() Int:
    print("hash")
    return self.id

type Rank:
    n: Int

// ms: allow_effect std.console.write
fn Rank.compare(other: Rank) Int:
    print("compare")
    return self.n - other.n

fn by_operator(a: Key, b: Key) Bool:
    return a == b

fn by_collection(items: List[Key], key: Key) Bool:
    return items.contains(key)

fn by_set(key: Key) Int:
    var seen = Set[Key]()
    seen.add(key)
    return seen.length()

fn by_nested(a: List[Key], b: List[Key]) Bool:
    return a != b

fn by_order(items: List[Rank]) Int:
    top := items.max()
    return (top?.n).get(0)

fn equality_only(a: Rank, b: Rank) Bool:
    return a.n == b.n

fn plain(items: List[Key]) Int:
    return items.length()

fn main() Unit:
    return
