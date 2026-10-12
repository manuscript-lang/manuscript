# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"

export type Decimal:
    fn to_float() -> Float
    fn truncate_to_int() -> Optional[Int]
