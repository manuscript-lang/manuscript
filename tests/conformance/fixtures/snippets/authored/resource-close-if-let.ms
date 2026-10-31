# conform: tags=scope-cleanup,tier-core
# conform: phase=run
# conform: origin=an if let payload resource closes when its branch ends
import stdout from "@std/io.ms"
import Closeable, TextError from "@std/core.ms"

fn say(s: String) Unit:
    stdout().write(s + "\n").get()

type Res:
    name: String

impl Closeable for Res:
    var fn close() Unit!:
        say("close {self.name}")
        return ok(unit)

fn maybe(name: String, present: Bool) Res?:
    return if present: Res(name) else: none

fn make(name: String) Res!TextError:
    return ok(Res(name))

fn keep(r: Res) Res:
    return r

fn early_return() Int:
    if let r = maybe("early", true):
        if r.name.length() > 1:
            return 1

        say("not here")

    return 0

fn local_optional() Unit:
    let o = maybe("local", true)
    if let r = o:
        say("body {r.name}")
    say("after local")

fn absent() Unit:
    if let r = maybe("absent", false):
        say("body {r.name}")
    else:
        say("else branch")

fn moved_on() Res:
    if let r = maybe("moved", true):
        return keep(r)

    return Res("fallback")

fn with_else_err() Unit:
    if let r = make("ok-result"):
        say("body {r.name}")

fn var_payload() Unit:
    if var r = maybe("var", true):
        r = Res("var-reassigned")
        say("body {r.name}")

export fn main() Int:
    early_return()
    local_optional()
    absent()

    let m = moved_on()
    say("moved_on got {m.name}")
    with_else_err()
    var_payload()
    say("end")
    return 0
