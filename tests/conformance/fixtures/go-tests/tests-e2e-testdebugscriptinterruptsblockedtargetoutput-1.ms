# conform: tags=modules,parser,stdlib-io,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/debug_script_cancel_unix_test.go:74 TestDebugScriptInterruptsBlockedTargetOutput
import stderr from "@std/io.ms"

export fn main() Int:
    let stream = stderr()
    let chunk = "
