package rt

import (
	"bytes"
	"io"
	"math"
)

// This file holds the helpers shared by the data-format, archive, crypto,
// random, path and html modules: budgets, bounded buffers and diagnostics.

// dfBudget resolves an optional byte, item or depth budget; an omitted
// budget imposes no cap.
func dfBudget(o Option[int64]) int64 {
	if o.Some {
		return o.Val
	}
	return math.MaxInt64
}

// dfMessage builds the fixed, input-independent diagnostic "domain: reason".
func dfMessage(domain, reason string) string { return domain + ": " + reason }

const (
	reasonInvalidInput  = "invalid input"
	reasonInvalidData   = "invalid data"
	reasonLimitExceeded = "limit exceeded"
	reasonUnsupported   = "operation not supported"
)

// dfBytes returns the contents of b; a missing Bytes is empty.
func dfBytes(b *Bytes) []byte {
	if b == nil {
		return nil
	}
	return b.Data
}

// dfLimitedWriter buffers output and fails once it would exceed max bytes.
type dfLimitedWriter struct {
	bytes.Buffer
	max      int64
	overflow bool
}

func (w *dfLimitedWriter) Write(p []byte) (int, error) {
	if int64(len(p)) > w.max-int64(w.Len()) {
		w.overflow = true
		return 0, io.ErrShortBuffer
	}
	return w.Buffer.Write(p)
}

// dfReadBounded reads reader to the end, failing with "LimitExceeded" when it
// yields more than max bytes and "InvalidData" on a read error.
func dfReadBounded(ctx *Execution, reader io.Reader, max int64) ([]byte, string) {
	var out bytes.Buffer
	buffer := make([]byte, 32768)
	for {
		CheckCancelled(ctx)
		remaining := max - int64(out.Len())
		chunk := buffer
		if remaining < int64(len(buffer)) {
			chunk = buffer[:int(remaining)+1]
		}
		n, err := reader.Read(chunk)
		if int64(n) > remaining {
			return nil, "LimitExceeded"
		}
		out.Write(chunk[:n])
		if err == io.EOF {
			return out.Bytes(), ""
		}
		if err != nil {
			return nil, "InvalidData"
		}
		if n == 0 {
			return nil, "Failed"
		}
	}
}
