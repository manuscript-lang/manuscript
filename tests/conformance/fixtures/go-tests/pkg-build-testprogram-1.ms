# conform: tags=control-flow,modules,parser,stdlib-io,tier-core
# conform: phase=parse
# conform: origin=pkg/build/replay_test.go:34 testProgram
import stdout from "@std/io.ms"

export fn main() Int:
    if stdout().write(data: %q).is_error():
        return 1
    return 0
