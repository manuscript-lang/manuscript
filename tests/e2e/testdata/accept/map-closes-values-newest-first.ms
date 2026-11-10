import (
    Closeable from "@std/core.ms",
    append_file, read_file, temporary from "@std/os/fs.ms",
    expect_equal, expect_ok from "@std/test/test.ms",
)

type Item:
    id: Int
    log: String

impl Closeable for Item:
    var fn close() Unit!:
        let _ = append_file(self.log, "{self.id},").wait()

fn logged(path: String) String:
    let read = read_file(path).wait()
    if let bytes = read: return bytes.decode_utf8().get("")

    return ""

fn fill(log: String) Unit:
    var items: Map[String, Item] = {}
    items.add("a", Item(id: 1, log: log.clone()))
    items.add("b", Item(id: 2, log: log.clone()))
    items.add("c", Item(id: 3, log: log.clone()))
    items.add("d", Item(id: 4, log: log.clone()))
    items.remove("b")  // the removed value closes at once

test "a map of resources closes the values it holds newest entry first at scope end":
    let tmp = temporary("ms-log-") | try expect_ok
    let log = "{tmp.path()}/log"
    fill(log.clone())
    logged(log.clone()) | try expect_equal("2,4,3,1,")
