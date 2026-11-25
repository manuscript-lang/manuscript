// conform: tags=diagnostics
// conform: phase=check
import NormalizationForm from "@std/string.ms"

fn wrong() Void {
	form := NormalizationForm.NFC
}
// expect-error: MS2001 6:31 unknown or non-nullary alternative case NFC of NormalizationForm; cases: Nfc, Nfd, Nfkc, Nfkd (cases with payloads need call syntax)
