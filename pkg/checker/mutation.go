package checker

// CollectionMutation reports whether a standard collection method mutates its receiver.
func CollectionMutation(receiver *Type, name string) bool {
	if std(receiver, "List") {
		switch name {
		case "append", "prepend", "insert", "pop", "set", "remove", "splice", "fill", "copy_within", "reverse_in_place":
			return true
		}
	}
	if std(receiver, "Map") {
		switch name {
		case "add", "remove", "add_default", "add_default_from", "merge", "clear":
			return true
		}
	}
	return std(receiver, "Set") && (name == "add" || name == "remove" || name == "clear")
}
