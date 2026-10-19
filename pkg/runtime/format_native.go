package msruntime

import (
	"strconv"
	"strings"
)

// FormatNative renders a native value as text: native types that print
// themselves implement fmt.Stringer, and resources print as [object].
func FormatNative(v any) string {
	if s, ok := v.(interface{ String() string }); ok {
		return s.String()
	}
	return "[object]"
}

// String renders Bytes as Bytes(1, 2, 3).
func (b *Bytes) String() string {
	parts := make([]string, len(b.Data))
	for i, x := range b.Data {
		parts[i] = strconv.Itoa(int(x))
	}
	return "Bytes(" + strings.Join(parts, ", ") + ")"
}

// Describe prints a contract value as its receiver: generated views implement
// Describe(depth); any other value prints as FormatNative does.
func Describe(v any, depth int) string {
	if d, ok := v.(interface{ Describe(int) string }); ok {
		return d.Describe(depth)
	}
	return FormatNative(v)
}
