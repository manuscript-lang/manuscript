// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=documentation/developer-tooling/builds/project-configuration.md:73
import (
	CustomerId from "./domain/customers.ms",
	Order from "@domain/orders.ms",
)
// expect-error: MS2002 4:1 cannot find module ./domain/customers.ms (looked for domain); check the spelling, make sure the file exists, and that the path is relative to the importing file
