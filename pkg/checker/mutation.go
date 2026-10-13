package checker

// CollectionMutation reports whether a standard collection method mutates its receiver.
func CollectionMutation(receiver *Type, name string) bool {
	if std(receiver, "List") {
		switch name {
		case "append", "prepend", "with_value", "without", "with_values", "fill", "copy_within", "reverse":
			return true
		}
	}
	if std(receiver, "Map") {
		switch name {
		case "add", "with_entry", "without", "with_default", "with_default_from", "merge", "clear":
			return true
		}
	}
	return std(receiver, "Set") && (name == "with_value" || name == "without" || name == "clear")
}
