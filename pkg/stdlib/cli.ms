# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"
import Map from "@std/collections.ms"

# Returns process arguments, excluding the executable path.
export fn arguments() -> List[String]:

# Returns the process environment as a map of variable names to values.
export fn environment() -> Map[String, String]:
