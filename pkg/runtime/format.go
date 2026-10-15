package msruntime

import "strings"

// The generated format functions own the depth guard (64 nested levels print
// "..."); these helpers join already-formatted parts.

// FormatList formats a list as `[a, b]`.
func FormatList[T any](l *List[T], elem func(T) string) string {
	var b strings.Builder
	b.WriteByte('[')
	for i, v := range l.Items {
		if i > 0 {
			b.WriteString(", ")
		}
		b.WriteString(elem(v))
	}
	b.WriteByte(']')
	return b.String()
}

// FormatSet formats a set as `Set(a, b)` in insertion order.
func FormatSet[T comparable](s *Set[T], elem func(T) string) string {
	var b strings.Builder
	b.WriteString("Set(")
	for i, v := range s.Snapshot() {
		if i > 0 {
			b.WriteString(", ")
		}
		b.WriteString(elem(v))
	}
	b.WriteByte(')')
	return b.String()
}

// FormatMap formats a map as `Map(k: v, ...)` in insertion order.
func FormatMap[K comparable, V any](m *Map[K, V], key func(K) string, value func(V) string) string {
	var b strings.Builder
	b.WriteString("Map(")
	for i, e := range m.Snapshot() {
		if i > 0 {
			b.WriteString(", ")
		}
		b.WriteString(key(e.Key))
		b.WriteString(": ")
		b.WriteString(value(e.Value))
	}
	b.WriteByte(')')
	return b.String()
}
