// conform: tags=formatter,interpolation,match,parser,strings,tier-core
// conform: phase=parse
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
