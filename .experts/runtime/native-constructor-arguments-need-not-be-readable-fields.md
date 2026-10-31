[Wiki](../index.md) › [Runtime](index.md)

# Native constructor arguments need not be readable fields

Verified: `Bytes(values: List[Int])` has a dedicated constructor rule; declaring `values` as a field did not make native Bytes expose that field. Keep the constructor signature separate from the native `values() -> List[Int]` operation, and keep editor constructor parameters (signature help) separate from receiver declarations. Constructor inputs and extracted lists copy byte values, preserving Bytes immutability.

Apply when: describing native schemas or replacing bogus native fields with operations.
Evidence: [byte declarations](../../stdlib/bytes.ms), [called extraction and constructor regressions](../../tests/e2e/testdata/stdlib/string-bytes.ms).
Verify: named and positional Bytes construction and direct, stored, and free extraction calls execute; mutating the input or extracted list leaves Bytes unchanged. Editor signature help retains the required values List; generated metadata lists `values` as an operation, with no data field.
