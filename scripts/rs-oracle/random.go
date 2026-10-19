package main

import (
	"math"
	"strconv"
	"strings"

	rt "github.com/manuscript-lang/manuscript/pkg/runtime"
)

// testEntropy serves a deterministic LCG byte stream, mirrored by tests/oracle.rs.
// kind "s<seed>" serves forever, "f<n>" fails with Failed("boom") once more than n bytes were
// requested, and "short" returns one byte fewer than requested.
type testEntropy struct {
	state  uint64
	kind   string
	served int
	limit  int
}

func newTestEntropy(kind string) *testEntropy {
	e := &testEntropy{kind: kind, state: 1}
	switch {
	case strings.HasPrefix(kind, "s"):
		e.state, _ = strconv.ParseUint(kind[1:], 10, 64)
	case strings.HasPrefix(kind, "f"):
		e.limit, _ = strconv.Atoi(kind[1:])
	}
	return e
}

func (e *testEntropy) Bytes(_ *rt.Execution, count int) rt.Result[*rt.Bytes, rt.RandomError] {
	n := count
	switch {
	case e.kind == "short":
		n = max(count-1, 0)
	case strings.HasPrefix(e.kind, "f"):
		if e.served+count > e.limit {
			return rt.Fail[*rt.Bytes, rt.RandomError](rt.RandomError_Failed{Message: "boom"})
		}
	}
	e.served += count
	b := make([]byte, n)
	for i := range b {
		e.state = e.state*6364136223846793005 + 1442695040888963407
		b[i] = byte(e.state >> 56)
	}
	return rt.Ok[*rt.Bytes, rt.RandomError](rt.NewBytes(b))
}

func randErr(e rt.RandomError) string {
	if f, ok := e.(rt.RandomError_Failed); ok {
		return "err Failed " + h(f.Message)
	}
	return "err " + errName(e)
}

func genRandom(dir string) {
	r := &recorder{}
	kinds := []string{"s0", "s1", "s7", "s123456789", "s18446744073709551615", "f0", "f1", "f5", "f40", "short"}
	maxes := []rt.Option[int]{rt.None[int](), rt.Some(1), rt.Some(2), rt.Some(3), rt.Some(10), rt.Some(100), rt.Some(255), rt.Some(256), rt.Some(257), rt.Some(65536), rt.Some(1000000007), rt.Some(1 << 53), rt.Some(9223372036854775807)}
	mins := []int{0, 1, -1, -100, -9223372036854775808, 5, 9223372036854775806, 9223372036854775807}
	for _, k := range kinds {
		for _, mn := range mins {
			for _, mx := range maxes {
				ms := "-"
				if mx.Some {
					ms = strconv.Itoa(mx.Val)
				}
				e := newTestEntropy(k)
				var vals []string
				for i := 0; i < 6; i++ {
					res := rt.Random_SecureInt(nil, e, mn, mx)
					if res.Failed {
						vals = append(vals, randErr(res.Err))
						break
					}
					vals = append(vals, "ok "+strconv.Itoa(res.Val))
				}
				r.row("int", k, strconv.Itoa(mn), ms, "=>", strings.Join(vals, ","))
			}
		}
		e := newTestEntropy(k)
		var vals []string
		for i := 0; i < 4; i++ {
			res := rt.Random_UuidV4(nil, e)
			if res.Failed {
				vals = append(vals, randErr(res.Err))
				break
			}
			vals = append(vals, "ok "+res.Val)
		}
		r.row("uuid", k, "=>", strings.Join(vals, ","))
		e = newTestEntropy(k)
		vals = nil
		for i := 0; i < 4; i++ {
			res := rt.Random_Float(nil, e)
			if res.Failed {
				vals = append(vals, randErr(res.Err))
				break
			}
			vals = append(vals, "ok "+strconv.FormatUint(floatBits(res.Val), 16))
		}
		r.row("float", k, "=>", strings.Join(vals, ","))
		for _, n := range []int{0, 1, 2, 3, 5, 10, 52, 300} {
			items := make([]int, n)
			for i := range items {
				items[i] = i
			}
			res := rt.Random_Shuffle(nil, newTestEntropy(k), rt.NewList(append([]int(nil), items...)...))
			if res.Failed {
				r.row("shuffle", k, strconv.Itoa(n), "=>", randErr(res.Err))
			} else {
				r.row("shuffle", k, strconv.Itoa(n), "=>", "ok "+intsText(res.Val.Items))
			}
			cr := rt.Random_Choice(nil, newTestEntropy(k), rt.NewList(items...))
			switch {
			case cr.Failed:
				r.row("choice", k, strconv.Itoa(n), "=>", randErr(cr.Err))
			case cr.Val.Some:
				r.row("choice", k, strconv.Itoa(n), "=>", "ok "+strconv.Itoa(cr.Val.Val))
			default:
				r.row("choice", k, strconv.Itoa(n), "=>", "ok none")
			}
		}
	}
	r.write(dir, "random.tsv")
}

func intsText(xs []int) string {
	s := make([]string, len(xs))
	for i, x := range xs {
		s[i] = strconv.Itoa(x)
	}
	return strings.Join(s, ",")
}

func floatBits(f float64) uint64 { return math.Float64bits(f) }
