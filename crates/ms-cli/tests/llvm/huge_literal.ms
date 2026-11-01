import stdout from "@std/io/io.ms"
import arguments from "@std/os/process.ms"

# The test replaces the one-element literal with 20000 runtime elements.
export fn main() Int:
    var o = stdout()
    let n = arguments().length()
    let xs = [n + 0]
    var t = 0
    for x in xs: t += x
    o.write("{t}\n").get()
    return 0
