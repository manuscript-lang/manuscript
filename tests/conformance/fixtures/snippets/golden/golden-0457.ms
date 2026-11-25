// conform: tags=diagnostics
// conform: phase=check
import HashAlgorithm from "@std/crypto/crypto.ms"

fn wrong() Void {
	algorithm := HashAlgorithm.Sha257
}
// expect-error: MS2001 6:32 unknown or non-nullary alternative case Sha257 of HashAlgorithm; cases: Md5, Sha1, Sha224, Sha256, Sha384, Sha3_256, Sha3_384, Sha3_512, Sha512 (cases with payloads need call syntax)
