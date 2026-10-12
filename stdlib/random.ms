# Canonical standard-library declarations. Implementations are native.

import Error from "@std/errors.ms"
import Bytes from "@std/bytes.ms"
import Result from "@std/result.ms"

export type RandomError:
    case InvalidInput
    case LimitExceeded
    case Failed(message: String)

export interface Entropy:
    fn bytes(count: Int) -> Result[Bytes, RandomError]

export fn secure_int(entropy: Entropy, min: Int, max_exclusive: Int) -> Result[Int, RandomError]

export fn uuid_v4(entropy: Entropy) -> Result[String, RandomError]

impl Error for RandomError:
    fn message() -> String

export fn entropy() -> Entropy
