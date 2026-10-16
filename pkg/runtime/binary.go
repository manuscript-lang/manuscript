package msruntime

import (
	"encoding/binary"
	"math"
)

func binaryFail[T any](e BinaryError) Result[T, BinaryError] { return Fail[T, BinaryError](e) }

func Errors_Message_BinaryError(_ *Execution, e BinaryError) string {
	switch e.(type) {
	case BinaryError_InvalidInput:
		return "binary: " + txInvalidInput
	case BinaryError_OutOfRange:
		return "binary: " + txOutOfRange
	}
	return "binary: operation failed"
}

func binaryOrder(little bool) binary.ByteOrder {
	if little {
		return binary.LittleEndian
	}
	return binary.BigEndian
}

func Binary_ReadInteger(_ *Execution, data *Bytes, offset, width int, signed, little bool) Result[int, BinaryError] {
	if width != 1 && width != 2 && width != 4 && width != 8 {
		return binaryFail[int](BinaryError_InvalidInput{})
	}
	if offset < 0 || offset > len(data.Data)-width {
		return binaryFail[int](BinaryError_OutOfRange{})
	}
	var n uint64
	chunk := data.Data[offset : offset+width]
	if little {
		for i := len(chunk) - 1; i >= 0; i-- {
			n = n<<8 | uint64(chunk[i])
		}
	} else {
		for _, v := range chunk {
			n = n<<8 | uint64(v)
		}
	}
	if signed && width < 8 && n&(uint64(1)<<(width*8-1)) != 0 {
		n |= ^uint64(0) << (width * 8)
	}
	if signed {
		v := int64(n)
		if int64(int(v)) != v {
			return binaryFail[int](BinaryError_OutOfRange{})
		}
		return Ok[int, BinaryError](int(v))
	}
	if n > math.MaxInt {
		return binaryFail[int](BinaryError_OutOfRange{})
	}
	return Ok[int, BinaryError](int(n))
}

func Binary_WriteInteger(_ *Execution, value, width int, signed, little bool) Result[*Bytes, BinaryError] {
	if width != 1 && width != 2 && width != 4 && width != 8 {
		return binaryFail[*Bytes](BinaryError_InvalidInput{})
	}
	if !signed && value < 0 || width < 8 && (signed && (int64(value) < -(int64(1)<<(width*8-1)) || int64(value) >= (int64(1)<<(width*8-1))) || !signed && uint64(value) >= (uint64(1)<<(width*8))) {
		return binaryFail[*Bytes](BinaryError_OutOfRange{})
	}
	b := make([]byte, width)
	v := uint64(value)
	for i := range b {
		at := i
		if !little {
			at = len(b) - 1 - i
		}
		b[at] = byte(v)
		v >>= 8
	}
	return Ok[*Bytes, BinaryError](NewBytes(b))
}

func Binary_ReadFloat(_ *Execution, data *Bytes, offset int, little bool) Result[float64, BinaryError] {
	if offset < 0 || offset > len(data.Data)-8 {
		return binaryFail[float64](BinaryError_OutOfRange{})
	}
	return Ok[float64, BinaryError](math.Float64frombits(binaryOrder(little).Uint64(data.Data[offset : offset+8])))
}

func Binary_WriteFloat(_ *Execution, value float64, little bool) *Bytes {
	b := make([]byte, 8)
	binaryOrder(little).PutUint64(b, math.Float64bits(value))
	return NewBytes(b)
}
