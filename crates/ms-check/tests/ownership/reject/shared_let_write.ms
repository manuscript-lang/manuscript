import Shared from "@std/concurrency/shared.ms"

fn f() Int:
    let items = Shared([1, 2])
    items.append(3)  # error: declared with let
    return items.length()
