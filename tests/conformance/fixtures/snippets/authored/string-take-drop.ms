// conform: tags=strings,tier-core
// conform: phase=run
// conform: origin=agent token study: String.take and String.drop
import stdout from "@std/io/io.ms"

fn main() Unit:
    var out = stdout()
    let s = "héllo"
    out.write(
        s.take(2) + "|" + s.drop(2) + "|" + s.take(99) + "|" + s.drop(
            99
        ) + "|" + s.drop(0) + "\n"
    ).get()
