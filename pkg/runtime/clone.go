package msruntime

import "maps"

// Clone copies a data value's own storage. Nested values retain their references.
func Clone(value Value) Value {
	switch v := value.(type) {
	case Record:
		return Record{v.Type, maps.Clone(v.Fields)}
	case Alternative:
		return Alternative{v.Type, v.Tag, append([]Value{}, v.Fields...)}
	case *List:
		return &List{v.Type, append([]Value{}, v.Items...)}
	case *Map:
		return &Map{Type: v.Type, Entries: append([]Entry{}, v.Entries...)}
	case *Set:
		return &Set{Type: v.Type, Items: append([]Value{}, v.Items...)}
	case Bytes:
		return Bytes{append([]byte{}, v.Items...)}
	default:
		return Panic("clone requires a record, alternative, or collection")
	}
}
