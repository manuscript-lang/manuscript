// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/modules/declarations.md:104
import CustomerId from "@customers"
// expect-error: MS2002 4:1 unknown import alias @customers; this project declares none, so add one under [aliases] in ms.toml, e.g. "@lib" = "./src/lib" (use @std/... for the standard library)
