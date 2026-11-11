import Closeable from "@std/core.ms"

type Item:
    id: Int

impl Closeable for Item:
    var fn close() Unit!:
        return ok(unit)

fn read(items: List[Item]) Int:
    if value := items.first():
        return value.id
    return 0
