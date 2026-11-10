// conform: tags=control-flow,interpolation,modules,stdlib-io,tier-core,try-result
// conform: phase=run
// conform: origin=documentation/learn/common-tasks.md:120
import stdin, stdout from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn run() Result[Unit, Error]:
    var input = lines(stdin())

    while true:
        let line = try input.next()

        if let text = line:
            try stdout().write("{text}\n")
        else:
            break

    return stdout().flush()

fn main() Unit!:
    try run()
