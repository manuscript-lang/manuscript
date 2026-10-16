package msruntime

import (
	"crypto/rand"
	"fmt"
	"math"
	"math/big"
)

// randomMaxBytes is the largest request an Entropy source must serve.
const randomMaxBytes = 16 * 1024 * 1024

// osEntropy is the operating system's cryptographic entropy source.
type osEntropy struct{}

var _ Entropy = osEntropy{}

// Bytes returns exactly count bytes, checking cancellation every 64 KiB.
func (osEntropy) Bytes(ctx *Execution, count int) Result[*Bytes, RandomError] {
	if count < 0 || count > randomMaxBytes {
		return Fail[*Bytes, RandomError](RandomError_InvalidInput{})
	}
	b := make([]byte, int(count))
	for offset := 0; offset < len(b); {
		CheckCancelled(ctx)
		end := min(offset+65536, len(b))
		if _, err := rand.Read(b[offset:end]); err != nil {
			return Fail[*Bytes, RandomError](RandomError_Failed{Message: err.Error()})
		}
		offset = end
	}
	return Ok[*Bytes, RandomError](NewBytes(b))
}

// Random_Entropy returns the operating system's entropy source.
func Random_Entropy(_ *Execution) Entropy { return osEntropy{} }

func randomIncorrectLength() RandomError {
	return RandomError_Failed{Message: "entropy source returned incorrect length"}
}

// Random_SecureInt returns an unbiased integer in [min, maxExclusive), with
// maxExclusive defaulting to the largest Int plus one.
func Random_SecureInt(ctx *Execution, entropy Entropy, min int, maxExclusive Option[int]) Result[int, RandomError] {
	max := math.MaxInt
	if maxExclusive.Some {
		max = maxExclusive.Val
	}
	if min >= max {
		return Fail[int, RandomError](RandomError_InvalidInput{})
	}
	width := new(big.Int).Sub(big.NewInt(int64(max)), big.NewInt(int64(min)))
	bits := width.BitLen()
	count := (bits + 7) / 8
	for {
		CheckCancelled(ctx)
		v := entropy.Bytes(ctx, int(count))
		if v.Failed {
			return Fail[int, RandomError](v.Err)
		}
		data := append([]byte{}, dfBytes(v.Val)...)
		if len(data) != count {
			return Fail[int, RandomError](randomIncorrectLength())
		}
		data[0] &= byte(255 >> uint(count*8-bits))
		n := new(big.Int).SetBytes(data)
		if n.Cmp(width) < 0 {
			return Ok[int, RandomError](int(n.Add(n, big.NewInt(int64(min))).Int64()))
		}
	}
}

// Random_UuidV4 builds a version-4 UUID from 16 bytes of entropy.
func Random_UuidV4(ctx *Execution, entropy Entropy) Result[string, RandomError] {
	v := entropy.Bytes(ctx, 16)
	if v.Failed {
		return Fail[string, RandomError](v.Err)
	}
	data := append([]byte{}, dfBytes(v.Val)...)
	if len(data) != 16 {
		return Fail[string, RandomError](randomIncorrectLength())
	}
	data[6] = data[6]&15 | 64
	data[8] = data[8]&63 | 128
	return Ok[string, RandomError](fmt.Sprintf("%x-%x-%x-%x-%x", data[:4], data[4:6], data[6:8], data[8:10], data[10:]))
}

// Errors_Message_RandomError returns Failed text verbatim, or "random: <reason>".
func Errors_Message_RandomError(_ *Execution, e RandomError) string {
	switch e := e.(type) {
	case RandomError_Failed:
		return e.Message
	case RandomError_InvalidInput:
		return dfMessage("random", reasonInvalidInput)
	case RandomError_LimitExceeded:
		return dfMessage("random", reasonLimitExceeded)
	}
	return dfMessage("random", "operation failed")
}
