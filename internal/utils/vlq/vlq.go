package vlq

import (
	"strings"
)

// Base64 characters used for VLQ encoding
const base64Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

// VLQ_BASE is the base for VLQ encoding (32)
const VLQ_BASE = 32

// VLQ_BASE_MASK is the mask for the base (31)
const VLQ_BASE_MASK = VLQ_BASE - 1

// VLQ_CONTINUATION_BIT is the continuation bit (32)
const VLQ_CONTINUATION_BIT = VLQ_BASE

// Encode encodes an integer using VLQ encoding
func Encode(value int) string {
	var result strings.Builder

	// Convert to unsigned representation
	vlq := toVLQSigned(value)

	for {
		digit := vlq & VLQ_BASE_MASK
		vlq >>= 5

		if vlq > 0 {
			digit |= VLQ_CONTINUATION_BIT
		}

		result.WriteByte(base64Chars[digit])

		if vlq == 0 {
			break
		}
	}

	return result.String()
}

// Decode decodes a VLQ-encoded string to an integer
func Decode(encoded string) (int, int, error) {
	var result int
	var shift uint
	var continuation bool
	var i int

	for i < len(encoded) {
		char := encoded[i]
		i++

		digit := fromBase64(char)
		if digit == -1 {
			return 0, i, nil // Invalid character, stop decoding
		}

		continuation = (digit & VLQ_CONTINUATION_BIT) != 0
		digit &= VLQ_BASE_MASK

		result += digit << shift
		shift += 5

		if !continuation {
			break
		}
	}

	return fromVLQSigned(result), i, nil
}

// DecodeMultiple decodes multiple VLQ values from a string
func DecodeMultiple(encoded string) ([]int, error) {
	var values []int
	pos := 0

	for pos < len(encoded) {
		value, consumed, err := Decode(encoded[pos:])
		if err != nil {
			return nil, err
		}

		if consumed == 0 {
			break // No more valid characters
		}

		values = append(values, value)
		pos += consumed
	}

	return values, nil
}

// toVLQSigned converts a signed integer to VLQ representation
func toVLQSigned(value int) int {
	if value < 0 {
		return ((-value) << 1) | 1
	}
	return value << 1
}

// fromVLQSigned converts from VLQ representation to signed integer
func fromVLQSigned(value int) int {
	isNegative := (value & 1) == 1
	value >>= 1
	if isNegative {
		return -value
	}
	return value
}

// fromBase64 converts a base64 character to its numeric value
func fromBase64(char byte) int {
	if char >= 'A' && char <= 'Z' {
		return int(char - 'A')
	}
	if char >= 'a' && char <= 'z' {
		return int(char - 'a' + 26)
	}
	if char >= '0' && char <= '9' {
		return int(char - '0' + 52)
	}
	if char == '+' {
		return 62
	}
	if char == '/' {
		return 63
	}
	return -1 // Invalid character
}
