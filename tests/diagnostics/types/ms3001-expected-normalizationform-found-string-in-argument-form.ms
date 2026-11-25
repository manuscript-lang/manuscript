// conform: tags=diagnostics
// conform: phase=check
import NormalizationForm from "@std/string.ms"

fn choose(form NormalizationForm) Void {
	return
}

fn wrong() Void {
	choose("NFC")
}
// expect-error: MS3001 10:12 expected NormalizationForm, found String (in argument 'form' of choose)
