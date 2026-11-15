import Closeable from "@std/core.ms"

type Marker:
    id: Int

fn var Marker.close() Void!: ok(void)

type Counter[T]:
    payload: T
    count: Int

fn var Counter[T].remove() Void:
    self.count += 1

fn var Counter[T].clear() Void:
    self.count += 1

fn var Counter[T].set() Void:
    self.count += 1

fn var Counter[T].add() Void:
    self.count += 1

fn var Counter[T].splice() Void:
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
