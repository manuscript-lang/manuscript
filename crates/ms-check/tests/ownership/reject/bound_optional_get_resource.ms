import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

fn inspect(value: Marker?) Int:
    let get = value.get  // error: this method value keeps its receiver for repeated calls, so it clones `Marker`, which has one owner and cannot be cloned; use it in place
    return get().id
