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
		return diagnostic("compression", reasonInvalidInput)
	case CompressionError_InvalidData:
		return diagnostic("compression", reasonInvalidData)
	case CompressionError_LimitExceeded:
		return diagnostic("compression", reasonLimit)
	case CompressionError_Unsupported:
		return diagnostic("compression", reasonUnsupported)
	}
	return diagnostic("compression", "operation failed")
}

// pullReader exposes a Manuscript ReadStream as an io.Reader, remembering the
// first stream failure so it can be reported with its original IoError.
type pullReader struct {
	ctx     *Execution
	in      ReadStream
	pending []byte
	err     IoError
}

func (r *pullReader) Read(p []byte) (int, error) {
	for len(r.pending) == 0 {
		CheckCancelled(r.ctx)
		v := r.in.Read(r.ctx, Some(len(p)))
		if v.Failed {
			r.err = v.Err
			return 0, io.ErrUnexpectedEOF
		}
		if !v.Val.Some {
			return 0, io.EOF
		}
		r.pending = v.Val.Val.Data
	}
	n := copy(p, r.pending)
	r.pending = r.pending[n:]
	return n, nil
}

// compressedStream lazily compresses or decompresses an input stream.
type compressedStream struct {
	in       ReadStream
	format   string
	level    int
	maxBytes int
	decode   bool
	src      *pullReader
	reader   io.Reader
	writer   io.WriteCloser
	buf      bytes.Buffer
	total    int
	done     bool
	failed   IoError
}

var _ ReadStream = (*compressedStream)(nil)

func (c *compressedStream) Close(ctx *Execution) Unit {
	c.in.Close(ctx)
	return Unit{}
}

func (c *compressedStream) start(ctx *Execution) IoError {
	c.src = &pullReader{ctx: ctx, in: c.in}
	var err error
	if c.decode {
		switch c.format {
		case "gzip":
			c.reader, err = gzip.NewReader(c.src)
		case "zlib":
			c.reader, err = zlib.NewReader(c.src)
		default:
			c.reader = flate.NewReader(c.src)
		}
	} else {
		switch c.format {
		case "gzip":
			c.writer, err = gzip.NewWriterLevel(&c.buf, c.level)
		case "zlib":
			c.writer, err = zlib.NewWriterLevel(&c.buf, c.level)
		default:
			c.writer, err = flate.NewWriter(&c.buf, c.level)
		}
	}
	if err != nil {
		return c.failure(err)
	}
	return nil
}

func (c *compressedStream) failure(err error) IoError {
	if c.src != nil && c.src.err != nil {
		return c.src.err
	}
	if c.decode {
		return IoError_InvalidData{}
	}
	return IoError_InvalidInput{}
}

func (c *compressedStream) Read(ctx *Execution, max Option[int]) Result[Option[*Bytes], IoError] {
	n := 65536
	if max.Some {
		if max.Val <= 0 {
			return Fail[Option[*Bytes], IoError](IoError_InvalidInput{})
		}
		n = max.Val
	}
	if c.failed != nil {
		return Fail[Option[*Bytes], IoError](c.failed)
	}
	if c.src == nil {
		if !c.decode && (c.level < 0 || c.level > 9) {
			c.failed = IoError_InvalidInput{}
		} else {
			c.failed = c.start(ctx)
		}
		if c.failed != nil {
			return Fail[Option[*Bytes], IoError](c.failed)
		}
	}
	c.src.ctx = ctx
	if c.decode {
		return c.readDecoded(n)
	}
	return c.readEncoded(ctx, n)
}

func (c *compressedStream) readDecoded(n int) Result[Option[*Bytes], IoError] {
	if c.done {
		return Ok[Option[*Bytes], IoError](None[*Bytes]())
	}
	out := make([]byte, n)
	for {
		got, err := c.reader.Read(out)
		if got > 0 {
			c.total += got
			if c.total > c.maxBytes {
				return Fail[Option[*Bytes], IoError](IoError_LimitExceeded{})
			}
			return Ok[Option[*Bytes], IoError](Some(NewBytes(out[:got])))
		}
		if err == io.EOF {
			c.done = true
			return Ok[Option[*Bytes], IoError](None[*Bytes]())
		}
		if err != nil {
			return Fail[Option[*Bytes], IoError](c.failure(err))
		}
	}
}

func (c *compressedStream) readEncoded(ctx *Execution, n int) Result[Option[*Bytes], IoError] {
	for c.buf.Len() == 0 && !c.done {
		CheckCancelled(ctx)
		v := c.in.Read(ctx, Some(32768))
		if v.Failed {
			return Fail[Option[*Bytes], IoError](v.Err)
		}
		var err error
		if v.Val.Some {
			_, err = c.writer.Write(v.Val.Val.Data)
		} else {
			err = c.writer.Close()
			c.done = true
		}
		if err != nil {
			return Fail[Option[*Bytes], IoError](c.failure(err))
		}
	}
	if c.buf.Len() == 0 {
		return Ok[Option[*Bytes], IoError](None[*Bytes]())
	}
	chunk := make([]byte, min(n, c.buf.Len()))
	c.buf.Read(chunk)
	return Ok[Option[*Bytes], IoError](Some(NewBytes(chunk)))
}

// CompressionFormat_CompressStream returns a stream of compressed input.
func CompressionFormat_CompressStream(_ *Execution, format CompressionFormat, input ReadStream, level int) ReadStream {
	return &compressedStream{in: input, format: compressionName(format), level: level}
}

// CompressionFormat_DecompressStream returns a stream of decompressed input.
func CompressionFormat_DecompressStream(_ *Execution, format CompressionFormat, input ReadStream, maxBytes Option[int]) ReadStream {
	limit := int(^uint(0) >> 1)
	if maxBytes.Some {
		limit = maxBytes.Val
	}
	return &compressedStream{in: input, format: compressionName(format), decode: true, maxBytes: limit}
}
