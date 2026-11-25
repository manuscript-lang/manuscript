// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
from "@std/io/io.ms" import stdout
// expect-error: MS1000 4:1-4:5 imports read: import name, other from "path.ms"
// expect-format-exit: 1
