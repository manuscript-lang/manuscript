import Closeable from "@std/core.ms"

type Item:
    id: Int

fn var Item.close() Void!:
    return ok()

fn read(items: List[Item]) Int:
    if value := items.first():
        return value.id
    return 0
