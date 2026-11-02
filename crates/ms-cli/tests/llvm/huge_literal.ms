import stdout from "@std/io/io.ms"

# The test replaces the one-element literal with 20000 constant elements.
export fn main() Int:
    var o = stdout()
    let xs = [0]
    var t = 0
    for x in xs: t += x
    o.write("{t}\n").get()
    return 0
