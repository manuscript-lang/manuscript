package msruntime

import (
	"encoding/base64"
	"encoding/hex"
	"strings"
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

func Encoding_HexDecode(_ *Execution, text string, maxBytes Option[int64]) Result[*Bytes, EncodingError] {
	n := txLimit(maxBytes)
	if n < 0 {
		return encodingFail[*Bytes](EncodingError_InvalidInput{})
	}
	if int64(len(text)/2) > n {
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

func Encoding_Base64Decode(_ *Execution, text string, urlSafe bool, maxBytes Option[int64]) Result[*Bytes, EncodingError] {
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
	if int64(len(text)/4)*3-int64(padding) > n {
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
	if int64(len(b)) > n {
		return encodingFail[*Bytes](EncodingError_LimitExceeded{})
	}
	return Ok[*Bytes, EncodingError](NewBytes(b))
}
