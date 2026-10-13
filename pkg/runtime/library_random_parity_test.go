package msruntime

import (
	"context"
	"math"
	"reflect"
	"sync"
	"testing"
)

type randomParityEntropy struct {
	requests []int64
	response func(*Execution, int64) Value
}

type randomParityDrawCancellation struct {
	context.Context
	changed func() bool
	cancel  context.CancelFunc
}

func (ctx *randomParityDrawCancellation) Err() error {
	if ctx.changed() {
		ctx.cancel()
	}
	return ctx.Context.Err()
}

func (entropy *randomParityEntropy) Operation(name string) Function {
	if name != "bytes" {
		Panic("unexpected entropy operation")
	}
	return NewFunction([]string{"count"}, "@std/Result[@std/Bytes][@std/RandomError]", func(ctx *Execution, args []Value) Value {
		count := args[0].(int64)
		entropy.requests = append(entropy.requests, count)
		return entropy.response(ctx, count)
	})
}

func randomParityZeroEntropy() *randomParityEntropy {
	return &randomParityEntropy{response: func(_ *Execution, count int64) Value {
		return libraryOK("@std/Result[@std/Bytes][@std/RandomError]", Bytes{make([]byte, count)})
	}}
}

func TestRandomParitySecureFloatEndpointsAndMalformedEntropy(t *testing.T) {
	result := "@std/Result[Float][@std/RandomError]"
	spec := libraryFunctions["random/secure_float"]
	for _, test := range []struct {
		byteValue byte
		want      float64
	}{{0, 0}, {255, 1 - math.Ldexp(1, -53)}} {
		entropy := &randomParityEntropy{response: func(_ *Execution, count int64) Value {
			data := make([]byte, count)
			for i := range data {
				data[i] = test.byteValue
			}
			return libraryOK("@std/Result[@std/Bytes][@std/RandomError]", Bytes{data})
		}}
		got := librarySuccess(t, spec.Body(RootExecution(), result, []Value{entropy})).(float64)
		if got != test.want || !reflect.DeepEqual(entropy.requests, []int64{8}) {
			t.Fatal("wrong 53-bit sampling", got, entropy.requests)
		}
	}
	for _, length := range []int{0, 7, 9} {
		entropy := &randomParityEntropy{response: func(_ *Execution, _ int64) Value {
			return libraryOK("@std/Result[@std/Bytes][@std/RandomError]", Bytes{make([]byte, length)})
		}}
		libraryFailure(t, spec.Body(RootExecution(), result, []Value{entropy}), "Failed")
	}
}

func TestRandomParitySecureChoiceAndShufflePreservePayloads(t *testing.T) {
	ctx := RootExecution()
	items := &List{Type: "@std/List[local/Item]", Items: []Value{Record{"local/Item", map[string]Value{"id": int64(1)}}, Record{"local/Item", map[string]Value{"id": int64(2)}}}}
	cause := Alternative{"@std/RandomError", "Failed", []Value{"original entropy detail"}}
	failed := &randomParityEntropy{response: func(_ *Execution, _ int64) Value {
		return Alternative{"@std/Result[@std/Bytes][@std/RandomError]", "error", []Value{cause}}
	}}
	for _, operation := range []struct{ name, result string }{
		{"secure_float", "@std/Result[Float][@std/RandomError]"},
		{"secure_choice", "@std/Result[@std/Optional[local/Item]][@std/RandomError]"},
		{"secure_shuffle", "@std/Result[@std/List[local/Item]][@std/RandomError]"},
	} {
		args := []Value{failed}
		if operation.name != "secure_float" {
			args = append(args, items)
		}
		out := libraryFunctions["random/"+operation.name].Body(ctx, operation.result, args).(Alternative)
		if out.Type != operation.result || out.Tag != "error" || &out.Fields[0].(Alternative).Fields[0] != &cause.Fields[0] {
			t.Fatal("entropy error payload or result identity changed", out)
		}
	}
	entropy := randomParityZeroEntropy()
	choiceResult := "@std/Result[@std/Optional[local/Item]][@std/RandomError]"
	chosen := librarySuccess(t, libraryFunctions["random/secure_choice"].Body(ctx, choiceResult, []Value{entropy, items})).(Alternative)
	if chosen.Type != "@std/Optional[local/Item]" || chosen.Tag != "some" || chosen.Fields[0].(Record).Fields["id"] != int64(1) {
		t.Fatal("choice lost the generic element type", chosen)
	}
	shuffleResult := "@std/Result[@std/List[local/Item]][@std/RandomError]"
	shuffled := librarySuccess(t, libraryFunctions["random/secure_shuffle"].Body(ctx, shuffleResult, []Value{entropy, items})).(*List)
	if shuffled == items || shuffled.Type != items.Type || &shuffled.Items[0] == &items.Items[0] {
		t.Fatal("shuffle reused input list storage", shuffled)
	}
	shuffled.Items[0].(Record).Fields["id"] = int64(9)
	if items.Items[1].(Record).Fields["id"] != int64(9) {
		t.Fatal("shuffle copied referenced records")
	}
	shuffled.Items[0] = int64(42)
	if _, ok := items.Items[1].(Record); !ok {
		t.Fatal("shuffle shares outer list storage")
	}
	for _, name := range []string{"secure_choice", "secure_shuffle"} {
		result := choiceResult
		if name == "secure_shuffle" {
			result = shuffleResult
		}
		libraryFailure(t, libraryFunctions["random/"+name].Body(ctx, result, []Value{&randomParityEntropy{response: func(_ *Execution, _ int64) Value {
			return libraryOK("@std/Result[@std/Bytes][@std/RandomError]", Bytes{})
		}}, items}), "Failed")
	}
	requests := len(entropy.requests)
	empty := libraryList("local/Item", nil)
	missing := librarySuccess(t, libraryFunctions["random/secure_choice"].Body(ctx, choiceResult, []Value{entropy, empty})).(Alternative)
	if missing.Type != "@std/Optional[local/Item]" || missing.Tag != "none" || len(entropy.requests) != requests {
		t.Fatal("empty choice read entropy or lost type", missing)
	}
	for _, list := range []*List{empty, libraryList("local/Item", items.Items[:1])} {
		out := librarySuccess(t, libraryFunctions["random/secure_shuffle"].Body(ctx, shuffleResult, []Value{entropy, list})).(*List)
		if out == list || len(entropy.requests) != requests {
			t.Fatal("trivial shuffle read entropy or reused input")
		}
	}
}

func TestRandomParitySplitMix64VectorsAndRejection(t *testing.T) {
	random := &libraryRandom{}
	for _, want := range []uint64{0xe220a8397b1dcdaf, 0x6e789e6aa1b965f4, 0x06c45d188009454f, 0xf88bb8a8724c81ec, 0x1b39896a51a8749b} {
		if got := random.next(); got != want {
			t.Fatalf("SplitMix64 sequence changed: got %016x, want %016x", got, want)
		}
	}
	ctx := RootExecution()
	random = &libraryRandom{state: 3}
	result := "@std/Result[Int][@std/RandomError]"
	out := librarySuccess(t, libraryFunctions["random/int"].Body(ctx, result, []Value{random, int64(math.MinInt64), int64(1)})).(int64)
	if out != -5528608851982440056 || random.state != 0x3c6ef372fe94f82d {
		t.Fatal("wide signed range did not reject the incomplete residue cycle", out, random.state)
	}
	initial := random.state
	libraryFailure(t, libraryFunctions["random/int"].Body(ctx, result, []Value{random, int64(3), int64(3)}), "InvalidInput")
	if random.state != initial {
		t.Fatal("invalid range advanced generator")
	}
	for _, max := range []Value{nil, optional("Int", nil, false), optional("Int", int64(-2), true)} {
		min := int64(-10)
		got := librarySuccess(t, libraryFunctions["random/int"].Body(ctx, result, []Value{random, min, max})).(int64)
		if got < min || max != nil && max.(Alternative).Tag == "some" && got >= -2 {
			t.Fatal("wrong optional signed range", got)
		}
	}
	input := libraryList("Int", []Value{int64(1), int64(2), int64(3)})
	first := libraryFunctions["random/shuffle"].Body(ctx, input.Type, []Value{&libraryRandom{state: 42}, input}).(*List)
	second := libraryFunctions["random/shuffle"].Body(ctx, input.Type, []Value{&libraryRandom{state: 42}, input}).(*List)
	if !Equal(first, second) || first == input || second == input || &first.Items[0] == &second.Items[0] {
		t.Fatal("seeded shuffle is not reproducible with fresh storage")
	}
}

func TestRandomParityCancellationPrecedesEffectsAndInterruptsWork(t *testing.T) {
	ctx := RootExecution()
	cancelledContext, cancel := context.WithCancel(ctx.Context)
	cancel()
	ctx.Context = cancelledContext
	entropy := randomParityZeroEntropy()
	random := &libraryRandom{state: 42}
	empty := libraryList("Int", nil)
	for _, operation := range []struct {
		name, result string
		args         []Value
	}{
		{"secure_float", "@std/Result[Float][@std/RandomError]", []Value{entropy}},
		{"secure_choice", "@std/Result[@std/Optional[Int]][@std/RandomError]", []Value{entropy, empty}},
		{"secure_shuffle", "@std/Result[@std/List[Int]][@std/RandomError]", []Value{entropy, empty}},
		{"seeded", "@std/Random", []Value{int64(1)}},
		{"int", "@std/Result[Int][@std/RandomError]", []Value{random, int64(1), int64(1)}},
		{"float", "Float", []Value{random}},
		{"choice", "@std/Optional[Int]", []Value{random, empty}},
		{"shuffle", "@std/List[Int]", []Value{random, empty}},
	} {
		failure := recovered(func() { libraryFunctions["random/"+operation.name].Body(ctx, operation.result, operation.args) })
		if _, ok := failure.(cancelled); !ok {
			t.Fatalf("cancelled %s became %#v", operation.name, failure)
		}
	}
	if random.state != 42 || len(entropy.requests) != 0 {
		t.Fatal("cancelled random call performed an effect")
	}
	for _, name := range []string{"secure_shuffle", "shuffle"} {
		workContext, cancelWork := context.WithCancel(context.Background())
		defer cancelWork()
		work := &stringWorkCancellation{Context: workContext, cancel: cancelWork}
		ctx := RootExecution()
		ctx.Context = work
		input := libraryList("Int", make([]Value, 4096))
		result, source := "@std/List[Int]", Value(random)
		if name == "secure_shuffle" {
			result, source = "@std/Result[@std/List[Int]][@std/RandomError]", entropy
		}
		failure := recovered(func() { libraryFunctions["random/"+name].Body(ctx, result, []Value{source, input}) })
		if _, ok := failure.(cancelled); !ok || work.checks < 2 {
			t.Fatalf("shuffle failed to cancel during copy: %#v (%d checks)", failure, work.checks)
		}
	}
	workContext, cancelWork := context.WithCancel(context.Background())
	defer cancelWork()
	work := &stringWorkCancellation{Context: workContext, cancel: cancelWork}
	ctx = RootExecution()
	ctx.Context = work
	random = &libraryRandom{state: 3}
	failure := recovered(func() { random.bounded(ctx, 1<<63+1) })
	if _, ok := failure.(cancelled); !ok || random.state != 0x9e3779b97f4a7c18 {
		t.Fatalf("rejection sampling failed to cancel before the second draw: %#v (%x)", failure, random.state)
	}
	for _, name := range []string{"secure_shuffle", "shuffle"} {
		ctx := RootExecution()
		workContext, cancelDraw := context.WithCancel(ctx.Context)
		defer cancelDraw()
		random := &libraryRandom{state: 42}
		entropy := randomParityZeroEntropy()
		ctx.Context = &randomParityDrawCancellation{Context: workContext, cancel: cancelDraw, changed: func() bool {
			return random.state != 42 || len(entropy.requests) > 0
		}}
		input := libraryList("Int", []Value{int64(1), int64(2), int64(3), int64(4)})
		result, source := input.Type, Value(random)
		if name == "secure_shuffle" {
			result, source = "@std/Result[@std/List[Int]][@std/RandomError]", entropy
		}
		failure := recovered(func() { libraryFunctions["random/"+name].Body(ctx, result, []Value{source, input}) })
		if _, ok := failure.(cancelled); !ok || !Equal(input, libraryList("Int", []Value{int64(1), int64(2), int64(3), int64(4)})) {
			t.Fatalf("shuffle did not cancel during draws while preserving input: %#v", failure)
		}
	}
}

func TestRandomParitySharedStateSynchronizesDraws(t *testing.T) {
	const workers, draws = 8, 64
	random := &libraryRandom{state: 7}
	words := make(chan uint64, workers*draws)
	var group sync.WaitGroup
	for i := 0; i < workers; i++ {
		group.Add(1)
		go func() {
			defer group.Done()
			for j := 0; j < draws; j++ {
				words <- random.next()
			}
		}()
	}
	group.Wait()
	close(words)
	want := map[uint64]int{}
	serial := &libraryRandom{state: 7}
	for i := 0; i < workers*draws; i++ {
		want[serial.next()]++
	}
	for word := range words {
		want[word]--
	}
	for word, count := range want {
		if count != 0 {
			t.Fatalf("concurrent calls repeated or lost a draw: %x (%d)", word, count)
		}
	}
}
