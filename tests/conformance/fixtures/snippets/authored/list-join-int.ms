// conform: tags=lists,strings,tier-core
// conform: phase=run
// conform: origin=agent token study: List[Int].join
import stdout from "@std/io/io.ms"

fn main() Unit:
    var out = stdout()
    out.write(
        [3, -1, 20].join(",") + "|" + List[Int]().join("x") + "|" + [7].join(
            "--"
        ) + "\n"
    ).get()
