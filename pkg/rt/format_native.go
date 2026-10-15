package rt

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

// String renders an OperationId as OperationId(n).
func (o *OperationId) String() string { return "OperationId(" + strconv.FormatUint(o.number, 10) + ")" }
