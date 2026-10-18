package msruntime

import (
	"errors"
	"fmt"
	"io"
	"math"
	"reflect"
	"strings"
	"testing"
)

type dfObservedReader struct {
	text     string
	requests []int
}

func (r *dfObservedReader) Read(p []byte) (int, error) {
	r.requests = append(r.requests, len(p))
	if r.text == "" {
		return 0, io.EOF
	}
	n := copy(p, r.text)
	r.text = r.text[n:]
	return n, nil
}

func TestDFReadBoundedLimitsAndReadSizes(t *testing.T) {
	ctx := RootExecution()
	for _, limit := range []int{0, 1, 64, 32766, 32767, 32768, math.MaxInt} {
		for _, hint := range []int{-1, 0, 1, 63, 32768, math.MaxInt} {
			for _, extra := range []int{0, 1} {
				t.Run(fmt.Sprintf("limit=%d/hint=%d/extra=%d", limit, hint, extra), func(t *testing.T) {
					size := min(limit, 32770) + extra
					reader := &dfObservedReader{text: strings.Repeat("x", size)}
					got, code := dfReadBounded(ctx, reader, limit, hint)
					wantCode := ""
					if size > limit {
						wantCode = "LimitExceeded"
					}
					if code != wantCode || code == "" && len(got) != size || code != "" && got != nil {
						t.Fatalf("read len=%d code=%q; size=%d want code=%q", len(got), code, size, wantCode)
					}
					// Preserve the old request sequence, including its declared-size
					// hint and exactly one byte of limit overshoot.
					chunk := 32768
					resolvedHint := max(0, min(hint, limit, 1<<20))
					if resolvedHint > 0 {
						chunk = min(chunk, resolvedHint+1)
					}
					var want []int
					consumed := 0
					for {
						request := chunk
						if limit-consumed < request {
							request = limit - consumed + 1
						}
						want = append(want, request)
						if consumed == size {
							break
						}
						n := min(request, size-consumed)
						consumed += n
						if consumed > limit {
							break
						}
					}
					if !reflect.DeepEqual(reader.requests, want) {
						t.Fatalf("Read lengths=%v want=%v", reader.requests, want)
					}
				})
			}
		}
	}
}

func TestDFReadBoundedReaderResults(t *testing.T) {
	ctx := RootExecution()
	for _, tt := range []struct {
		name string
		err  error
		data string
		max  int
		want string
		code string
	}{
		{"empty EOF", io.EOF, "", 0, "", ""},
		{"data with EOF", io.EOF, "abc", 3, "abc", ""},
		{"limit before EOF", io.EOF, "abcd", 3, "", "LimitExceeded"},
		{"read error", errors.New("read failed"), "abc", 3, "", "InvalidData"},
		{"limit before read error", errors.New("read failed"), "abcd", 3, "", "LimitExceeded"},
		{"no progress", nil, "", 3, "", "Failed"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			reader := boundedReadFunc(func(p []byte) (int, error) { return copy(p, tt.data), tt.err })
			got, code := dfReadBounded(ctx, reader, tt.max, 0)
			if string(got) != tt.want || code != tt.code {
				t.Fatalf("read=%q,%q; want=%q,%q", got, code, tt.want, tt.code)
			}
		})
	}
}

func TestDFReadBoundedCancelledBeforeRead(t *testing.T) {
	ctx, cancel := cancelledExecution()
	cancel()
	defer func() {
		if _, ok := recover().(cancelled); !ok {
			t.Fatal("expected cancellation before reading")
		}
	}()
	reader := boundedReadFunc(func([]byte) (int, error) {
		t.Fatal("cancelled read reached reader")
		return 0, io.EOF
	})
	dfReadBounded(ctx, reader, 64, 0)
}
