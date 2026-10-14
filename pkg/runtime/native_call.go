package msruntime

// NativeCall is a standard-library operation on a receiver whose kind the
// checker fixed, bound once per call site. It runs the same library body, with
// the same cancellation, propagation and equality scope, as the bound Function
// that NativeMemberResult builds, without constructing that Function, matching
// argument labels or copying an argument slice on every call.
type NativeCall struct {
	function Function
	scope    TypeScope
	scoped   bool
	// A member without a library body falls back to ordinary dispatch.
	name, result string
	scopes       []TypeScope
}

// BindNativeCall resolves kind.name once. Collections select the receiver's
// equality scope per call; scalars never consult it, so they skip the copy.
// Set.map and Map.map_keys deduplicate outputs, so their second scope wins.
func BindNativeCall(kind, name, native, result string, scopes ...TypeScope) Value {
	spec, ok := libraryFunctions[native]
	if !ok {
		return &NativeCall{name: name, result: result, scopes: scopes}
	}
	labels := make([]string, len(spec.Params))
	for i, p := range spec.Params {
		labels[i] = p.Name
	}
	call := &NativeCall{name: name, result: result, scopes: scopes, function: NewFunction(labels, result, func(ctx *Execution, args []Value) Value {
		return invokeLibrary(spec, ctx, result, args)
	})}
	switch kind {
	case "List", "Map", "Set":
		call.scoped = true
		call.scope = scopes[0]
		if len(call.scope.Args) > 0 {
			call.scope = call.scope.Args[0]
		}
		if outputKeys := kind == "Set" && name == "map" || kind == "Map" && name == "map_keys"; outputKeys && len(scopes) > 1 && len(scopes[1].Args) > 0 {
			call.scope = scopes[1].Args[0]
		}
	}
	return call
}

// CallNative runs a bound operation; args holds the receiver, then the
// operation's arguments in declaration order.
func CallNative(ctx *Execution, bound Value, args []Value) Value {
	call := bound.(*NativeCall)
	CheckCancelled(ctx)
	if call.function.Body == nil {
		return NativeMemberResult(args[0], call.name, call.result, call.scopes...).(Function).Body(ctx, args[1:])
	}
	if call.scoped {
		child := *ctx
		child.EqualityScope = call.scope
		ctx = &child
	}
	return call.function.Body(ctx, args)
}
