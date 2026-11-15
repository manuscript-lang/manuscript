// conform: tags=scope-cleanup,tier-core
// conform: phase=run
// conform: origin=an if let payload resource closes when its branch ends
import stdout from "@std/io/io.ms"
import Closeable from "@std/core.ms"

fn say(s: String) Void:
    stdout().write(s + "\n").get()

type Res:
    name: String

fn var Res.close() Void!:
    say("close {self.name}")

fn maybe(name: String, present: Bool) Res?:
    return if present: Res(name) else: none

fn make(name: String) Res!Error:
    return ok(Res(name))

fn keep(r: Res) Res:
    return r

fn early_return() Int:
    if r := maybe("early", true):
        if r.name.length() > 1:
            return 1

        say("not here")

    return 0

fn local_optional() Void:
    o := maybe("local", true)
    if r := o:
        say("body {r.name}")
    say("after local")

fn absent() Void:
    if r := maybe("absent", false):
        say("body {r.name}")
    else:
        say("else branch")

fn moved_on() Res:
    if r := maybe("moved", true):
        return keep(r)

    return Res("fallback")

fn with_else_err() Void:
    if r := make("ok-result"):
        say("body {r.name}")

fn var_payload() Void:
    if var r = maybe("var", true):
        r = Res("var-reassigned")
        say("body {r.name}")

fn main() Void:
    early_return()
    local_optional()
    absent()

    m := moved_on()
    say("moved_on got {m.name}")
    with_else_err()
    var_payload()
    say("end")
