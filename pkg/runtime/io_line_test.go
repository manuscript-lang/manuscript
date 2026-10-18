package msruntime

import (
	"context"
	"errors"
	"reflect"
	"sync"
	"testing"
)

func (p *lineProbe) Close(*Execution) Unit { return Unit{} }

type lineProbe struct {
	data    []byte
	reads   int
	failure IoError
}

func (p *lineProbe) Read(ctx *Execution, max Option[int]) Result[Option[*Bytes], IoError] {
	p.reads++
	CheckCancelled(ctx)
	if p.failure != nil {
		return Fail[Option[*Bytes]](p.failure)
	}
	if len(p.data) == 0 {
		return Ok[Option[*Bytes], IoError](None[*Bytes]())
	}
	n := len(p.data)
	if max.Some {
		n = min(n, max.Val)
	}
	data := p.data[:n:n]
	p.data = p.data[n:]
	return Ok[Option[*Bytes], IoError](Some(&Bytes{Data: data}))
}

type bufferedLineProbe struct {
	lineProbe
	mu    sync.Mutex
	ahead readAhead
}

func (p *bufferedLineProbe) lineBuffer() (*sync.Mutex, *readAhead) { return &p.mu, &p.ahead }

func TestHasLinePreservesReadLineConsumption(t *testing.T) {
	for _, tc := range []struct {
		name, data string
		limit      Option[int]
	}{
		{"empty", "", None[int]()}, {"empty line", "\n", None[int]()}, {"crlf", "a\r\nb\nlast", None[int]()},
		{"unicode", "λ\nø\r\n尾", None[int]()}, {"invalid utf8", "\xff\ngood\n", None[int]()},
		{"limit exact", "abc\ngood\n", Some(3)}, {"limit below", "abc\nx\n", Some(2)},
		{"crlf limit", "ab\r\nx\n", Some(3)}, {"tail limit", "abc", Some(3)},
		{"invalid limit", "a\nb\n", Some(0)},
	} {
		for _, buffered := range []bool{false, true} {
			t.Run(tc.name+map[bool]string{true: " buffered", false: " custom"}[buffered], func(t *testing.T) {
				var a, b ReadStream
				pa, pb := &lineProbe{data: []byte(tc.data)}, &lineProbe{data: []byte(tc.data)}
				if buffered {
					a = &bufferedLineProbe{lineProbe: *pa}
					b = &bufferedLineProbe{lineProbe: *pb}
				} else {
					a, b = pa, pb
				}
				for i := 0; i < 10; i++ {
					expected := Io_ReadLine(nil, a, tc.limit)
					if got := Io_HasLine(nil, b, tc.limit); got != (!expected.Failed && expected.Val.Some) {
						t.Fatalf("step%d presence %v vs %+v", i, got, expected)
					}
					// Interleave an ordinary text read: the optimized read must leave exactly
					// the same pending bytes, not merely the same first Bool.
					x, y := Io_ReadLine(nil, a, None[int]()), Io_ReadLine(nil, b, None[int]())
					if !reflect.DeepEqual(x, y) {
						t.Fatalf("step%d following text %+v vs %+v", i, x, y)
					}
				}
			})
		}
	}
}

type countingLineContext struct {
	context.Context
	polls     int
	cancelled bool
}

func (c *countingLineContext) Err() error {
	c.polls++
	if c.cancelled {
		return context.Canceled
	}
	return nil
}
func TestHasLinePreservesCancellationQueries(t *testing.T) {
	for _, buffered := range []bool{false, true} {
		count := &countingLineContext{Context: context.Background()}
		ctx := &Execution{Context: count}
		if buffered {
			input := &bufferedLineProbe{ahead: readAhead{buf: []byte("first\nsecond\n")}}
			if !Io_HasLine(ctx, input, None[int]()) || count.polls != 0 {
				t.Fatal("buffered path added a query")
			}
			count.cancelled = true
			if !Io_HasLine(ctx, input, None[int]()) || count.polls != 0 {
				t.Fatal("buffered cancellation behavior changed")
			}
		} else {
			input := &lineProbe{data: []byte("a\n")}
			if !Io_HasLine(ctx, input, None[int]()) || count.polls != 2 {
				t.Fatalf("byte reads queried %d times", count.polls)
			}
			count.cancelled = true
			func() {
				defer func() {
					if _, ok := recover().(cancelled); !ok {
						t.Fatal("missing cancellation unwind")
					}
				}()
				Io_HasLine(ctx, input, None[int]())
			}()
		}
	}
}
func TestHasLineCustomFailure(t *testing.T) {
	stream := &lineProbe{failure: IoError_Failed{Message: errors.New("failure").Error()}}
	if Io_HasLine(nil, stream, None[int]()) || stream.reads != 1 {
		t.Fatal("custom stream error changed")
	}
}

func TestHasLineBufferedSlowQueries(t *testing.T) {
	for _, presence := range []bool{false, true} {
		count := &countingLineContext{Context: context.Background()}
		ctx := &Execution{Context: count}
		input := &bufferedLineProbe{lineProbe: lineProbe{data: []byte("a\nb\n")}}
		if presence {
			if !Io_HasLine(ctx, input, None[int]()) {
				t.Fatal("missing line")
			}
		} else {
			if Io_ReadLine(ctx, input, None[int]()).Val.Val != "a" {
				t.Fatal("wrong line")
			}
		}
		if count.polls != 1 || input.reads != 1 {
			t.Fatalf("slow path: polls=%d reads=%d", count.polls, input.reads)
		}
		count.cancelled = true
		// The buffered second line retains the ordinary no-query path.
		if presence {
			if !Io_HasLine(ctx, input, None[int]()) {
				t.Fatal("missing buffered line")
			}
		} else {
			if Io_ReadLine(ctx, input, None[int]()).Val.Val != "b" {
				t.Fatal("wrong buffered line")
			}
		}
		if count.polls != 1 {
			t.Fatal("buffered path added a query")
		}
		func() {
			defer func() {
				if _, ok := recover().(cancelled); !ok {
					t.Fatal("missing slow-path cancellation")
				}
			}()
			if presence {
				Io_HasLine(ctx, input, None[int]())
			} else {
				Io_ReadLine(ctx, input, None[int]())
			}
		}()
		if count.polls != 2 {
			t.Fatal("wrong slow-path cancellation query count")
		}
	}
}
