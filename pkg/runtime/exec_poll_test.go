package msruntime

import (
	"context"
	"math"
	"testing"
)

type pollCountingContext struct {
	context.Context
	queries int
	done    bool
}

func (c *pollCountingContext) Err() error {
	c.queries++
	if c.done {
		return context.Canceled
	}
	return nil
}

func TestPollPhaseAndCancellation(t *testing.T) {
	for _, start := range []uint32{0, 62, 63, math.MaxUint32 - 1, math.MaxUint32} {
		c := &pollCountingContext{Context: context.Background()}
		tick := start
		for i := 0; i < 130; i++ {
			before := c.queries
			Poll(&Execution{Context: c}, &tick)
			expectedTick := start + uint32(i+1)
			if tick != expectedTick {
				t.Fatalf("start=%d iteration=%d: tick=%d, want %d", start, i, tick, expectedTick)
			}
			want := 0
			if expectedTick&63 == 0 {
				want = 1
			}
			if c.queries-before != want {
				t.Fatalf("start=%d iteration=%d tick=%d: queries=%d", start, i, tick, c.queries-before)
			}
		}
	}
	for _, index := range []int{math.MinInt, -65, -64, -1, 0, 62, 63, 64, 127, math.MaxInt} {
		c := &pollCountingContext{Context: context.Background()}
		PollIndex(&Execution{Context: c}, index)
		want := 0
		if index&63 == 63 {
			want = 1
		}
		if c.queries != want {
			t.Fatalf("index=%d queries=%d", index, c.queries)
		}
	}
	for _, indexed := range []bool{false, true} {
		c := &pollCountingContext{Context: context.Background(), done: true}
		e := &Execution{Context: c}
		tick := uint32(62)
		if indexed {
			PollIndex(e, 62)
		} else {
			Poll(e, &tick)
		}
		if c.queries != 0 {
			t.Fatal("queried before selected poll")
		}
		func() {
			defer func() {
				if _, ok := recover().(cancelled); !ok {
					t.Fatal("poll lost cancellation identity")
				}
			}()
			if indexed {
				PollIndex(e, 63)
			} else {
				Poll(e, &tick)
			}
		}()
		if c.queries != 1 {
			t.Fatalf("cancellation queries=%d", c.queries)
		}
		tick = 63
		if indexed {
			PollIndex(Shield(e), 63)
		} else {
			Poll(Shield(e), &tick)
		}
		if c.queries != 1 {
			t.Fatal("shield queried cancelled parent")
		}
	}
	tick := uint32(63)
	Poll(nil, &tick)
	PollIndex(nil, 63)
	tick = 63
	Poll(&Execution{Context: context.Background()}, &tick)
	PollIndex(&Execution{Context: context.Background()}, 63)
}
