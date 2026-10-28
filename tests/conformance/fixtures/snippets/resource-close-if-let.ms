# conform: tags=with-cleanup,tier-core
# conform: phase=run
# conform: origin=an if let payload resource closes when its branch ends
from "@std/io.ms" import stdout
from "@std/core.ms" import Closeable, TextError

def say(s: String) -> Unit:
    stdout().write(s + "\n").get()

type Res:
    name: String

impl Closeable for Res:
    var def close() -> Unit:
        say(f"close {self.name}")

def maybe(name: String, present: Bool) -> Optional[Res]:
    return some(Res(name)) if present else none

def make(name: String) -> Result[Res, TextError]:
    return ok(Res(name))

def keep(r: Res) -> Res:
    return r

def early_return() -> Int:
    if let r = maybe("early", True):
        if r.name.length() > 1:
            return 1
        say("not here")
    return 0

def local_optional() -> Unit:
    let o = maybe("local", True)
    if let r = o:
        say(f"body {r.name}")
    say("after local")

def absent() -> Unit:
    if let r = maybe("absent", False):
        say(f"body {r.name}")
    else:
        say("else branch")

def moved_on() -> Res:
    if let r = maybe("moved", True):
        return keep(r)
    return Res("fallback")

def with_else_err() -> Unit:
    if let r = make("ok-result"):
        say(f"body {r.name}")

export def main() -> Int:
    early_return()
    local_optional()
    absent()
    let m = moved_on()
    say(f"moved_on got {m.name}")
    with_else_err()
    say("end")
    return 0
