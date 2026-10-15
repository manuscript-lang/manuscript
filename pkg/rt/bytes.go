package rt

// Bytes is a mutable byte sequence shared by aliases.
type Bytes struct {
	Data []byte
}

// NewBytes returns Bytes holding data without copying it.
func NewBytes(data []byte) *Bytes { return &Bytes{Data: data} }

// BytesBuilder is implemented by the bytes module.
type BytesBuilder struct{}
