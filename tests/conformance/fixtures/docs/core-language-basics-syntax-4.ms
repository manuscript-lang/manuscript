// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/basics/syntax.md:50
import Customer from "./greeting.ms"
// expect-error: MS2002 4:1 cannot find module ./greeting.ms (looked for greeting.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
