# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"
import Map from "@std/collections.ms"

export fn arguments() -> List[String]

export fn environment() -> Map[String, String]
