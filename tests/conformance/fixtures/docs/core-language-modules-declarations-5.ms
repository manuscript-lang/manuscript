// conform: tags=diagnostics,records,strings,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/modules/declarations.md:75
type PrivateToken {
	value String
}

// Rejected: callers cannot name the internal result type.
export fn issue() PrivateToken {
	return PrivateToken("token")
}
// expect-error: MS3000 9:8 public signature exposes private type PrivateToken; add 'export' to its declaration or keep the function private
