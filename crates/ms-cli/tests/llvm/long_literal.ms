import stdout from "@std/io/io.ms"
import arguments from "@std/os/process.ms"

# The test replaces the one-element literal with 40000 runtime elements.
export fn main() Int:
    var o = stdout()
    let n = arguments().length()
    let xs = [n + 0]
    var t = 0
    for i in 0..xs.length(): t = (t * 31 + xs[i]) % 1000003
    o.write("{t} {xs.length()}\n").get()
    return 0
