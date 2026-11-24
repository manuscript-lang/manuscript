// conform: tags=diagnostics
// conform: phase=check
import NormalizationForm from "@std/string.ms"

fn choose(form NormalizationForm) Void {
	return
}

fn wrong() Void {
	choose("NFC")
}
