// conform: tags=diagnostics,optional,strings,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/optional_test.go:68 TestOptionalMethodsRejectInvalidContracts
fn wrong(value Int!String) Bool {
	return value.is_some()
}
// expect-error: MS2001 5:18 unknown or ambiguous member is_some on Result[Int, String]; available: and_then, err, get, get_or, get_or_else, is_error, is_ok, map, map_error, or_else, to_optional
