// conform: tags=diagnostics,formatter,modules,stdlib-crypto,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/compiler/codec_selectors_test.go:20 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
import HashAlgorithm from "@std/crypto/crypto.ms"

fn wrong() Void {
	algorithm := HashAlgorithm.Sha257
}
// expect-error: MS2001 7:32 unknown or non-nullary alternative case Sha257 of HashAlgorithm; cases: Md5, Sha1, Sha224, Sha256, Sha384, Sha3_256, Sha3_384, Sha3_512, Sha512 (cases with payloads need call syntax)
