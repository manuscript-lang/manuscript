package msruntime

import (
	"bytes"
	"unicode/utf8"
)

// Bytes is a mutable byte sequence shared by aliases.
type Bytes struct {
	Data []byte
}

// NewBytes returns Bytes holding data without copying it.
func NewBytes(data []byte) *Bytes { return &Bytes{Data: data} }

// Equal compares contents; the lowerer calls it for == on Bytes.
func (b *Bytes) Equal(_ *Execution, other *Bytes) bool { return bytes.Equal(b.Data, other.Data) }

// BytesBuilder accumulates bytes. Freeze seals it; further writes fault.
type BytesBuilder struct {
	data   []byte
	sealed bool
}

// NewBytesBuilder returns an empty builder.
func NewBytesBuilder() *BytesBuilder { return &BytesBuilder{} }

func BytesBuilder_Append(ctx *Execution, b *BytesBuilder, value int) Unit {
	CheckCancelled(ctx)
	if b.sealed {
		Raise("builder is sealed")
	}
	if value < 0 || value > 255 {
		txRangeFault("BytesBuilder.append", "value", value, 0, 255)
	}
	b.data = append(b.data, byte(value))
	return Unit{}
}

func BytesBuilder_Concat(ctx *Execution, b *BytesBuilder, values *Bytes) Unit {
	CheckCancelled(ctx)
	if b.sealed {
		Raise("builder is sealed")
	}
	b.data = append(b.data, values.Data...)
	return Unit{}
}

func BytesBuilder_Freeze(ctx *Execution, b *BytesBuilder) *Bytes {
	CheckCancelled(ctx)
	if !b.sealed {
		b.sealed = true
		b.data = b.data[:len(b.data):len(b.data)]
	}
	return NewBytes(b.data)
}

func Bytes_Values(_ *Execution, b *Bytes) *List[int] {
	out := make([]int, len(b.Data))
	for i, v := range b.Data {
		out[i] = int(v)
	}
	return NewList(out...)
}

func Bytes_Clone(_ *Execution, b *Bytes) *Bytes { return NewBytes(append([]byte{}, b.Data...)) }

func Bytes_Contains(_ *Execution, b, value *Bytes) bool { return bytes.Contains(b.Data, value.Data) }

func Bytes_Split(ctx *Execution, b, separator *Bytes, maxParts Option[int]) *List[*Bytes] {
	limit := txLimit(maxParts)
	if limit < 0 {
		txFaultNegative("split", "max_parts", limit)
	}
	data, sep := b.Data, separator.Data
	out := NewList[*Bytes]()
	if len(sep) == 0 {
		for i := 0; i < len(data) && len(out.Items) < limit; i++ {
			if i%1024 == 0 {
				CheckCancelled(ctx)
			}
			out.Items = append(out.Items, NewBytes(data[i:i+1:i+1]))
		}
		return out
	}
	start := 0
	for len(out.Items) < limit {
		CheckCancelled(ctx)
		offset := bytes.Index(data[start:], sep)
		CheckCancelled(ctx)
		if offset < 0 {
			out.Items = append(out.Items, NewBytes(data[start:len(data):len(data)]))
			break
		}
		end := start + offset
		out.Items = append(out.Items, NewBytes(data[start:end:end]))
		start = end + len(sep)
	}
	return out
}

// Bytes_Slice shares storage with the receiver; the capacity limit keeps
// appends from touching the parent.
func Bytes_Slice(_ *Execution, b *Bytes, start, end int) Result[*Bytes, CollectionError] {
	s, e, ok := txSliceBounds(len(b.Data), start, end)
	if !ok {
		return Fail[*Bytes, CollectionError](CollectionError_OutOfRange{})
	}
	return Ok[*Bytes, CollectionError](NewBytes(b.Data[s:e:e]))
}

// Bytes_Get returns the byte at a possibly negative index, else the default;
// an invalid index without a default is a fault.
func Bytes_Get(_ *Execution, b *Bytes, index int, def Option[int]) int {
	i := txRelative(len(b.Data), index)
	if i < 0 || i >= len(b.Data) {
		return missingIndex(index, len(b.Data), def)
	}
	return int(b.Data[i])
}

func Bytes_IndexOf(_ *Execution, b, value *Bytes) Option[int] {
	if i := bytes.Index(b.Data, value.Data); i >= 0 {
		return Some(int(i))
	}
	return None[int]()
}

func Bytes_LastIndexOf(_ *Execution, b, value *Bytes) Option[int] {
	if i := bytes.LastIndex(b.Data, value.Data); i >= 0 {
		return Some(int(i))
	}
	return None[int]()
}

func Bytes_StartsWith(_ *Execution, b, prefix *Bytes) bool {
	return bytes.HasPrefix(b.Data, prefix.Data)
}
func Bytes_EndsWith(_ *Execution, b, suffix *Bytes) bool { return bytes.HasSuffix(b.Data, suffix.Data) }

func Bytes_Reversed(ctx *Execution, b *Bytes) *Bytes {
	out := append([]byte{}, b.Data...)
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		if i%4096 == 0 {
			CheckCancelled(ctx)
		}
		out[i], out[j] = out[j], out[i]
	}
	return NewBytes(out)
}

// Bytes_WithValue returns a copy with one byte replaced; the index is checked
// before the value.
func Bytes_WithValue(_ *Execution, b *Bytes, index, value int) *Bytes {
	i := txRelative(len(b.Data), index)
	if i < 0 || i >= len(b.Data) {
		txIndexFault("Bytes.with_value", len(b.Data), index)
	}
	if value < 0 || value > 255 {
		txRangeFault("Bytes.with_value", "value", value, 0, 255)
	}
	out := append([]byte{}, b.Data...)
	out[i] = byte(value)
	return NewBytes(out)
}

func Bytes_IsEmpty(_ *Execution, b *Bytes) bool { return len(b.Data) == 0 }

func Bytes_Concat(_ *Execution, a, b *Bytes) *Bytes {
	out := make([]byte, 0, len(a.Data)+len(b.Data))
	return NewBytes(append(append(out, a.Data...), b.Data...))
}

func Bytes_Length(_ *Execution, b *Bytes) int { return len(b.Data) }

func Bytes_DecodeUtf8(_ *Execution, b *Bytes) Option[string] {
	if !utf8.Valid(b.Data) {
		return None[string]()
	}
	return Some(string(b.Data))
}

// NewBytesFromValues is the Bytes constructor: every value must fit a byte.
func NewBytesFromValues(values *List[int]) *Bytes {
	data := make([]byte, len(values.Items))
	for i, v := range values.Items {
		if v < 0 || v > 255 {
			rangeFault("Bytes", "values["+FormatInt(int(i))+"]", v, 0, 255)
		}
		data[i] = byte(v)
	}
	return &Bytes{Data: data}
}
