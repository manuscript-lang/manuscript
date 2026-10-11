# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"
import Result from "@std/result.ms"

export type Queue[T: Shareable]:
    capacity: Int
    fn close() -> Unit
    fn receive() -> Optional[T]
    fn send(value: T) -> Result[Unit, QueueError]

export type QueueError:
    case Closed
