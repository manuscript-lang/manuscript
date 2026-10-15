package hostos

import "time"

// Number is one native stat field. Field widths and signedness differ by host,
// so it keeps the signed or unsigned value exactly as the host reports it.
type Number struct {
	Signed     int64
	Unsigned   uint64
	IsUnsigned bool
}

// Int returns the value as int64, or zero when it does not fit.
func (n Number) Int() int64 {
	if n.IsUnsigned {
		if n.Unsigned > 1<<63-1 {
			return 0
		}
		return int64(n.Unsigned)
	}
	return n.Signed
}

// Stat holds the native stat fields a host provides; Valid is false when the
// host exposes none, and every field is then zero.
type Stat struct {
	Valid                                            bool
	Blksize, Blocks, Rdev, Dev, Ino, Nlink, Uid, Gid Number
	Atime, Ctime                                     time.Time
}

type integer interface {
	~int | ~int8 | ~int16 | ~int32 | ~int64 | ~uint | ~uint8 | ~uint16 | ~uint32 | ~uint64 | ~uintptr
}

func number[T integer](v T) Number {
	var zero T
	if ^zero > 0 {
		return Number{Unsigned: uint64(v), IsUnsigned: true}
	}
	return Number{Signed: int64(v)}
}
