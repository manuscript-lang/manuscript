// conform: tags=records,stdlib-crypto,stdlib-testing,testing,tier-stdlib
// conform: phase=test
// conform: origin=perf thread: HashAlgorithm operations stored as function values
import (
	HashAlgorithm, sha256, sha512 from "@std/crypto.ms",
	expect_equal from "@std/test/test.ms",
)

test "stored HashAlgorithm operations match direct calls":
	data := "abc".to_bytes()
	key := "key".to_bytes()
	digest := HashAlgorithm.Sha256.digest
	expect_equal(digest(data), sha256(data))?

	hmac := HashAlgorithm.Sha512.hmac
	expect_equal(hmac(key, data)?, HashAlgorithm.Sha512.hmac(key, data)?)?
	expect_equal((hmac(key, data)?).length(), sha512(data).length())?
