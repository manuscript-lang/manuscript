# conform: tags=records,stdlib-crypto,stdlib-testing,testing,tier-stdlib
# conform: phase=test
# conform: origin=perf thread: HashAlgorithm operations stored as function values
import expect_equal from "@std/test.ms"
import {HashAlgorithm, sha256, sha512} from "@std/crypto.ms"

test "stored HashAlgorithm operations match direct calls":
    let data = "abc".to_bytes()
    let key = "key".to_bytes()
    let digest = HashAlgorithm.Sha256.digest
    try expect_equal(digest(data), sha256(data))

    let hmac = HashAlgorithm.Sha512.hmac
    try expect_equal(try hmac(key, data), try HashAlgorithm.Sha512.hmac(key, data))
    try expect_equal((try hmac(key, data)).length(), sha512(data).length())
