from "@std/test.ms" import expect_equal, expect_false, expect_ok, expect_true
from "@std/fs.ms" import filesystem

# A value known only by its interface, as `filesystem().open` hands back a FileHandle.
interface Handle:
    var def close() -> Unit
    def id() -> Int

type Resource:
    dir: String
    number: Int

impl Handle for Resource:
    var def close() -> Unit:
        let _ = filesystem().write_file(f"{self.dir}/{self.number}", "closed", True)

    def id() -> Int:
        return self.number

def open_handle(dir: String, number: Int) -> Handle:
    return Resource(dir, number)

def closed(dir: String, number: Int) -> Bool:
    return filesystem().read_file(f"{dir}/{number}").is_ok()

def falls_off_the_end(dir: String) -> Int:
    let handle = open_handle(dir, 1)
    return handle.id()

def hands_it_on(dir: String) -> Handle:
    let handle = open_handle(dir, 2)
    return handle

test "an interface handle is closed when its scope ends":
    with let temporary = filesystem().temporary("manuscript-implicit-") | try expect_ok:
        try expect_equal(falls_off_the_end(temporary.path()), 1)
        try expect_true(closed(temporary.path(), 1))

test "a returned interface handle stays open for the caller":
    with let temporary = filesystem().temporary("manuscript-implicit-") | try expect_ok:
        let kept = hands_it_on(temporary.path())
        try expect_equal(kept.id(), 2)
        try expect_false(closed(temporary.path(), 2))
