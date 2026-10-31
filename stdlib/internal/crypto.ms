import Bytes from "@std/bytes.ms"

export extern fn msrt_crypto_constant_time_equal(left: Bytes, right: Bytes) Bool

export extern fn msrt_crypto_verify(key: Bytes, data: Bytes, signature: Bytes) Bool
