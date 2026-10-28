# conform: tags=aliasing,control-flow,faults,formatter,interfaces,maps,match,modules,parser,stdlib-testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/map_add_scope/first.ms
import Key from "./domain.ms"
import {insert, insert_bound} from "./helper.ms"
import expect_equal from "@std/test.ms"

impl Equal for Key:
    fn equals(other: Key) Bool:
        return (self.code == other.code or self.code == -other.code)

impl Hashable for Key:
    fn hash() Int: 0

export fn first() Result[Int, Error]:
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
