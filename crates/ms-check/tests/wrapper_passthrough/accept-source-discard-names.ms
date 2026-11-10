import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

type Counter[T]:
    payload: T
    count: Int

impl Counter[T]:
    var fn remove() Unit:
        self.count += 1

    var fn clear() Unit:
        self.count += 1

    var fn set() Unit:
        self.count += 1

    var fn add() Unit:
        self.count += 1

    var fn splice() Unit:
        self.count += 1

fn demo() Int:
    var counter = Counter(Marker(1), 0)
    remove_action := counter.remove
    remove_action()
    clear_action := counter.clear
    clear_action()
    set_action := counter.set
    set_action()
    add_action := counter.add
    add_action()
    splice_action := counter.splice
    splice_action()
    return counter.count
