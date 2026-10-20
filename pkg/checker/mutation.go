package checker

// CollectionMutation reports whether a standard collection method mutates its
// receiver. List, Map and Set methods say so with `var fn` in their @std
// declaration; the builders are shared handles declared with plain `fn`, so
// their mutating methods are listed here.
func CollectionMutation(method *Method) bool {
	if method == nil || method.Decl == nil {
		return false
	}
	receiver, name := method.Receiver, method.Decl.Name
	switch {
	case std(receiver, "StringBuilder"):
		return name == "append" || name == "freeze"
	case std(receiver, "BytesBuilder"):
		return name == "append" || name == "concat" || name == "freeze"
	case std(receiver, "List"), std(receiver, "Map"), std(receiver, "Set"):
		return method.Decl.Mutating
	}
	return false
}
