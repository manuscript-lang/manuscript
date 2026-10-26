# conform: tags=aliasing,control-flow,faults,formatter,interfaces,maps,match,modules,parser,stdlib-testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/map_add_scope/first.ms
from "./domain.ms" import Key
from "./helper.ms" import insert, insert_bound
from "@std/testing.ms" import expect_equal

impl Equal for Key:
    def equals(other: Key) -> Bool:
        return (
            self.code == other.code
            or self.code == -other.code
        )

impl Hashable for Key:
    def hash() -> Int: 0

export def first() -> Result[Int, Error]:
    var m = Map[Key, Int]()
    var original = Key(1.0)
    m.add(original, 1)
    insert(var m, Key(-1.0), 2)
    insert_bound(var m, Key(1.0), 3)

    let add = m.add
    add(value: 4, key: Key(2.0))
    m.get(Key(1.0)).get() | try expect_equal(3)
    original.code = 9.0
    m.keys() [0].code | try expect_equal(9.0)
    return ok(m.length())
