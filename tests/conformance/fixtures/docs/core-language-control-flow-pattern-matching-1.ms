// conform: tags=diagnostics,interpolation,match,strings,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/control-flow/pattern-matching.md:12
fn describe(payment Payment) String {
	match payment {
		Paid(receipt) => {
			return f"Paid: {receipt}"
		}
		Declined(reason) => {
			return f"Declined: {reason}"
		}
		Pending(reference) => {
			return f"Pending: {reference}"
		}
	}
}
// expect-error: MS2001 4:21 unknown type Payment; declare it with 'type Payment:' / 'enum Payment:' / 'interface Payment:', declare it as a type parameter, or import it
