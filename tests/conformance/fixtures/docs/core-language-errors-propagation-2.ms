# conform: tags=diagnostics,modules,stdlib-errors,strings,tier-stdlib,try-result
# conform: phase=check
# conform: origin=documentation/core-language/errors/propagation.md:24
from "@std/core.ms" import TextError

def prepare() -> Result[Unit, TextError]: ok(())

def ready_label() -> Result[String, TextError]:
    try prepare()
    return ok("ready")
