# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import LibraryError from "@std/errors.ms"
import Result from "@std/result.ms"

export fn constant_time_equal(left: Bytes, right: Bytes) -> Bool

export fn derive_key(password: Bytes, salt: Bytes, iterations: Int, length: Int) -> Result[Bytes, LibraryError]

export fn hmac(key: Bytes, data: Bytes, algorithm: String) -> Result[Bytes, LibraryError]

export fn open(key: Bytes, nonce: Bytes, ciphertext: Bytes, associated_data: Bytes) -> Result[Bytes, LibraryError]

export fn public_key(seed: Bytes) -> Result[Bytes, LibraryError]

export fn seal(key: Bytes, nonce: Bytes, plaintext: Bytes, associated_data: Bytes) -> Result[Bytes, LibraryError]

export fn sha256(data: Bytes) -> Bytes

export fn sha384(data: Bytes) -> Bytes

export fn sha512(data: Bytes) -> Bytes

export fn sign(seed: Bytes, data: Bytes) -> Result[Bytes, LibraryError]

export fn verify(key: Bytes, data: Bytes, signature: Bytes) -> Bool
