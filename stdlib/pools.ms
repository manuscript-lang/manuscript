# Canonical standard-library declarations. Implementations are native.

import Error from "@std/errors.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"

export type Lease[T: Shareable]:
    fn close() -> Unit
    fn get() -> Result[T, PoolError]

export type Pool[T: Shareable]:
    resources: List[T]
    fn acquire() -> Result[Lease[T], PoolError]
    fn close() -> Unit

export type PoolError:
    case Closed

impl Error for PoolError:
    fn message() -> String
