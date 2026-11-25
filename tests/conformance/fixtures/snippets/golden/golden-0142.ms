// conform: tags=diagnostics
// conform: phase=check
fn wrong() Result[Void, JsonError] {
	return error(cause: EncodingError.InvalidData)
}
