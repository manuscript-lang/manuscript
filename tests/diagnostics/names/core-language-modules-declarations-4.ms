// conform: tags=diagnostics,formatter,modules,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/modules/declarations.md:65
import CustomerId from "./domain/customers.ms"
// expect-error: MS2002 4:1 cannot find module ./domain/customers.ms (looked for domain); check the spelling, make sure the file exists, and that the path is relative to the importing file
