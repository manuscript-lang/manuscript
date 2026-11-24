// conform: tags=scope-cleanup,maps,tier-io
// conform: phase=run
// `main` skips freeing plain memory at exit, but what it holds that closes still closes, in order,
// whether the resource sits in a binding, a list, or a record beside plain data.
import Closeable from "@std/core.ms"

type Gate:
    id Int

fn move Gate.close() Void!:
    print(f"closed {self.id}")
    return ok()

type Holder:
    name String
    gates List[Gate]
    words Map[String, List[String]]

fn main() Void:
    var words = Map[String, List[String]]()
    for i in 0..1000:
        words[f"key-number-{i}-padding"] = [f"value-one-{i}", f"value-two-{i}"]
    plain := ["a string long enough to live on the heap", "another one of the same kind"]
    held := Holder("holder name that is long enough to be on the heap", [Gate(2), Gate(3)], words)
    first := Gate(1)
    print(f"{plain.length()} {held.gates.length()} {first.id}")
