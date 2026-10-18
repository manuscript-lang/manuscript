package msruntime

import (
	"encoding/base64"
	"encoding/hex"
	"strings"
	"unicode/utf16"
)

func encodingFail[T any](e EncodingError) Result[T, EncodingError] {
	return Fail[T, EncodingError](e)
}

func Errors_Message_EncodingError(_ *Execution, e EncodingError) string {
	switch e.(type) {
	case EncodingError_InvalidInput:
		return "encoding: " + txInvalidInput
	case EncodingError_InvalidData:
		return "encoding: " + txInvalidData
	case EncodingError_LimitExceeded:
		return "encoding: " + txLimitExceeded
	}
	return "encoding: operation failed"
}

func Encoding_HexEncode(_ *Execution, data *Bytes) string { return hex.EncodeToString(data.Data) }

func Encoding_HexDecode(_ *Execution, text string, maxBytes Option[int]) Result[*Bytes, EncodingError] {
	n := txLimit(maxBytes)
	if n < 0 {
		return encodingFail[*Bytes](EncodingError_InvalidInput{})
	}
	if int(len(text)/2) > n {
		return encodingFail[*Bytes](EncodingError_LimitExceeded{})
	}
	b, err := hex.DecodeString(text)
	if err != nil {
		return encodingFail[*Bytes](EncodingError_InvalidData{})
	}
	return Ok[*Bytes, EncodingError](NewBytes(b))
}

func Encoding_Base64Encode(_ *Execution, data *Bytes, urlSafe bool) string {
	enc := base64.StdEncoding
	if urlSafe {
		enc = base64.URLEncoding
	}
	return enc.EncodeToString(data.Data)
}

func Encoding_Base64Decode(_ *Execution, text string, urlSafe bool, maxBytes Option[int]) Result[*Bytes, EncodingError] {
	n := txLimit(maxBytes)
	if n < 0 {
		return encodingFail[*Bytes](EncodingError_InvalidInput{})
	}
	if strings.ContainsAny(text, "\r\n\t ") {
		return encodingFail[*Bytes](EncodingError_InvalidData{})
	}
	padding := len(text) - len(strings.TrimRight(text, "="))
	if padding > 2 || len(text)%4 != 0 {
		return encodingFail[*Bytes](EncodingError_InvalidData{})
	}
	if int(len(text)/4)*3-int(padding) > n {
		return encodingFail[*Bytes](EncodingError_LimitExceeded{})
	}
	enc := base64.StdEncoding
	if urlSafe {
		enc = base64.URLEncoding
	}
	b, err := enc.Strict().DecodeString(text)
	if err != nil {
		return encodingFail[*Bytes](EncodingError_InvalidData{})
	}
	if len(b) > n {
		return encodingFail[*Bytes](EncodingError_LimitExceeded{})
	}
	return Ok[*Bytes, EncodingError](NewBytes(b))
}

// Encoding_Utf16Encode encodes text as UTF-16 code units.
func Encoding_Utf16Encode(_ *Execution, text string, littleEndian bool) *Bytes {
	units := utf16.Encode([]rune(text))
	out := make([]byte, 0, len(units)*2)
	for _, unit := range units {
		if littleEndian {
			out = append(out, byte(unit), byte(unit>>8))
		} else {
			out = append(out, byte(unit>>8), byte(unit))
		}
	}
	return NewBytes(out)
}

// Encoding_Utf16Decode decodes strict UTF-16, rejecting odd lengths and unpaired surrogates.
func Encoding_Utf16Decode(_ *Execution, data *Bytes, littleEndian bool, maxBytes Option[int]) Result[string, EncodingError] {
	if txLimit(maxBytes) < 0 {
		return encodingFail[string](EncodingError_InvalidInput{})
	}
	raw := dfBytes(data)
	if len(raw)%2 != 0 {
		return encodingFail[string](EncodingError_InvalidData{})
	}
	units := make([]uint16, len(raw)/2)
	for i := range units {
		if littleEndian {
			units[i] = uint16(raw[2*i]) | uint16(raw[2*i+1])<<8
		} else {
			units[i] = uint16(raw[2*i])<<8 | uint16(raw[2*i+1])
		}
	}
	var out strings.Builder
	for i := 0; i < len(units); i++ {
		unit := rune(units[i])
		switch {
		case unit >= 0xD800 && unit < 0xDC00:
			if i+1 >= len(units) || units[i+1] < 0xDC00 || units[i+1] > 0xDFFF {
				return encodingFail[string](EncodingError_InvalidData{})
			}
			unit = utf16.DecodeRune(unit, rune(units[i+1]))
			i++
		case unit >= 0xDC00 && unit <= 0xDFFF:
			return encodingFail[string](EncodingError_InvalidData{})
		}
		out.WriteRune(unit)
		if out.Len() > txLimit(maxBytes) {
			return encodingFail[string](EncodingError_LimitExceeded{})
		}
	}
	return Ok[string, EncodingError](out.String())
}

func encodeNarrow(text string, limit rune) Result[*Bytes, EncodingError] {
	out := make([]byte, 0, len(text))
	for _, r := range text {
		if r > limit {
			return encodingFail[*Bytes](EncodingError_InvalidData{})
		}
		out = append(out, byte(r))
	}
	return Ok[*Bytes, EncodingError](NewBytes(out))
}

// Encoding_Latin1Encode encodes scalars up to U+00FF as single bytes.
func Encoding_Latin1Encode(_ *Execution, text string) Result[*Bytes, EncodingError] {
	return encodeNarrow(text, 0xFF)
}

// Encoding_Latin1Decode maps each byte to the scalar of the same value.
func Encoding_Latin1Decode(_ *Execution, data *Bytes) string {
	raw := dfBytes(data)
	out := make([]rune, len(raw))
	for i, b := range raw {
		out[i] = rune(b)
	}
	return string(out)
}

// Encoding_AsciiEncode encodes scalars up to U+007F as single bytes.
func Encoding_AsciiEncode(_ *Execution, text string) Result[*Bytes, EncodingError] {
	return encodeNarrow(text, 0x7F)
}

// Encoding_AsciiDecode rejects bytes above 0x7F.
func Encoding_AsciiDecode(_ *Execution, data *Bytes) Result[string, EncodingError] {
	raw := dfBytes(data)
	for _, b := range raw {
		if b > 0x7F {
			return encodingFail[string](EncodingError_InvalidData{})
		}
	}
	return Ok[string, EncodingError](string(raw))
}
