import expect_equal from "@std/test/test.ms"

type Bucket:
    keys: List[Int] = []
    names: List[String] = []
    size: Int = 0

impl Bucket:
    var fn add(key: Int, name: String) Unit:
        self.keys.append(key)
        self.names.append(name)
        self.size += 1

type Shelf:
    buckets: List[Bucket] = []
    spare: Bucket = Bucket()

type Store:
    shelf: Shelf = Shelf()

impl Store:
    var fn put(at: Int, key: Int) Unit:
        self.shelf.buckets[at].add(key, "k{key}")

test "var method on a list element changes only that element":
    var store = Store()
    store.shelf.buckets = [Bucket(), Bucket(), Bucket()]
    for i in [0, 1, 2, 1, 1]:
        store.put(i, i * 10)
    try expect_equal(store.shelf.buckets[0].keys, [0])
    try expect_equal(store.shelf.buckets[1].keys, [10, 10, 10])
    try expect_equal(store.shelf.buckets[1].names, ["k10", "k10", "k10"])
    try expect_equal(store.shelf.buckets[2].size, 1)

test "var method on a field and on an element of a local list":
    var shelf = Shelf()
    shelf.spare.add(7, "seven")
    shelf.buckets = [Bucket()]
    shelf.buckets[0].add(1, "one")
    shelf.buckets[0].add(2, "two")
    try expect_equal(shelf.spare.names, ["seven"])
    try expect_equal(shelf.buckets[0].size, 2)

test "argument read from the same list":
    var shelf = Shelf()
    shelf.buckets = [Bucket(), Bucket()]
    shelf.buckets[1].add(5, "five")
    shelf.buckets[0].add(shelf.buckets[1].size, "from-one")
    try expect_equal(shelf.buckets[0].keys, [1])
    try expect_equal(shelf.buckets[1].keys, [5])
