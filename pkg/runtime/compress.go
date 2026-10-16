package msruntime

import (
	"bytes"
	"compress/flate"
	"compress/gzip"
	"compress/zlib"
	"io"
)

func compressionName(f CompressionFormat) string {
	switch f.(type) {
	case CompressionFormat_Gzip:
		return "gzip"
	case CompressionFormat_Zlib:
		return "zlib"
	case CompressionFormat_Deflate:
		return "deflate"
	}
	Raise("invalid CompressionFormat receiver")
	return ""
}

// CompressionFormat_Compress compresses data with a typed format selector.
func CompressionFormat_Compress(ctx *Execution, format CompressionFormat, data *Bytes, level int, maxBytes Option[int]) Result[*Bytes, CompressionError] {
	CheckCancelled(ctx)
	return Compress_Compress(ctx, data, compressionName(format), level, maxBytes)
}

// CompressionFormat_Decompress decompresses data with a typed format selector.
func CompressionFormat_Decompress(ctx *Execution, format CompressionFormat, data *Bytes, maxBytes Option[int]) Result[*Bytes, CompressionError] {
	CheckCancelled(ctx)
	return Compress_Decompress(ctx, data, compressionName(format), maxBytes)
}

// Compress_Compress compresses with exactly "gzip", "zlib" or "deflate".
// Level must be 0..9 and maxBytes bounds the encoded output.
func Compress_Compress(ctx *Execution, data *Bytes, format string, level int, maxBytes Option[int]) Result[*Bytes, CompressionError] {
	max := dfBudget(maxBytes)
	if level < 0 || level > 9 || max < 0 {
		return Fail[*Bytes, CompressionError](CompressionError_InvalidInput{})
	}
	w := &dfLimitedWriter{max: max}
	var writer io.WriteCloser
	var err error
	switch format {
	case "gzip":
		writer, err = gzip.NewWriterLevel(w, int(level))
	case "zlib":
		writer, err = zlib.NewWriterLevel(w, int(level))
	case "deflate":
		writer, err = flate.NewWriter(w, int(level))
	default:
		return Fail[*Bytes, CompressionError](CompressionError_Unsupported{})
	}
	if err != nil {
		return Fail[*Bytes, CompressionError](CompressionError_InvalidInput{})
	}
	defer writer.Close()
	input := dfBytes(data)
	for len(input) > 0 {
		CheckCancelled(ctx)
		n := min(len(input), 65536)
		if _, err = writer.Write(input[:n]); err != nil {
			return Fail[*Bytes, CompressionError](CompressionError_LimitExceeded{})
		}
		input = input[n:]
	}
	if err = writer.Close(); err != nil {
		return Fail[*Bytes, CompressionError](CompressionError_LimitExceeded{})
	}
	return Ok[*Bytes, CompressionError](NewBytes(append([]byte{}, w.Bytes()...)))
}

// Compress_Decompress decompresses exactly "gzip", "zlib" or "deflate",
// rejecting trailing bytes and bounding the cumulative output.
func Compress_Decompress(ctx *Execution, data *Bytes, format string, maxBytes Option[int]) Result[*Bytes, CompressionError] {
	max := dfBudget(maxBytes)
	if max < 0 {
		return Fail[*Bytes, CompressionError](CompressionError_InvalidInput{})
	}
	input := bytes.NewReader(dfBytes(data))
	var reader io.ReadCloser
	var err error
	switch format {
	case "gzip":
		reader, err = gzip.NewReader(input)
	case "zlib":
		reader, err = zlib.NewReader(input)
	case "deflate":
		reader = flate.NewReader(input)
	default:
		return Fail[*Bytes, CompressionError](CompressionError_Unsupported{})
	}
	if err != nil {
		return Fail[*Bytes, CompressionError](CompressionError_InvalidData{})
	}
	defer reader.Close()
	b, code := dfReadBounded(ctx, reader, max, 0)
	switch code {
	case "":
	case "LimitExceeded":
		return Fail[*Bytes, CompressionError](CompressionError_LimitExceeded{})
	case "Failed":
		return Fail[*Bytes, CompressionError](CompressionError_Failed{Message: ""})
	default:
		return Fail[*Bytes, CompressionError](CompressionError_InvalidData{})
	}
	if input.Len() != 0 {
		return Fail[*Bytes, CompressionError](CompressionError_InvalidData{})
	}
	return Ok[*Bytes, CompressionError](NewBytes(b))
}

// Errors_Message_CompressionError returns Failed text verbatim, or a fixed
// compression diagnostic.
func Errors_Message_CompressionError(_ *Execution, e CompressionError) string {
	switch e := e.(type) {
	case CompressionError_Failed:
		return e.Message
	case CompressionError_InvalidInput:
		return dfMessage("compression", reasonInvalidInput)
	case CompressionError_InvalidData:
		return dfMessage("compression", reasonInvalidData)
	case CompressionError_LimitExceeded:
		return dfMessage("compression", reasonLimitExceeded)
	case CompressionError_Unsupported:
		return dfMessage("compression", reasonUnsupported)
	}
	return dfMessage("compression", "operation failed")
}
