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
	items := NewList("@std/List[local/Item]", []Value{Record{"local/Item", map[string]Value{"id": int64(1)}}, Record{"local/Item", map[string]Value{"id": int64(2)}}})
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
	if shuffled == items || shuffled.Type != items.Type {
		t.Fatal("shuffle reused input list storage", shuffled)
	}
	shuffled.Get(0).(Record).Fields["id"] = int64(9)
	if items.Get(1).(Record).Fields["id"] != int64(9) {
		t.Fatal("shuffle copied referenced records")
	}
	shuffled.Set(0, int64(42))
	if _, ok := items.Get(1).(Record); !ok {
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
	for _, list := range []*List{empty, items.CopySlice(0, 1)} {
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
	if !Equal(first, second) || first == input || second == input {
		t.Fatal("seeded shuffle is not reproducible with fresh storage")
	}
	first.Set(0, int64(99))
	if second.Get(0) == int64(99) || input.Get(0) != int64(1) {
		t.Fatal("seeded shuffled lists share mutable backing")
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
		input := NewIntList("@std/List[Int]", make([]int64, 4096))
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

func TestRandomParityPrimitiveAndBoxedListStorage(t *testing.T) {
	payloads := []Value{NewIntList("@std/List[Int]", []int64{1}), NewIntList("@std/List[Int]", []int64{2}), NewIntList("@std/List[Int]", []int64{3}), NewIntList("@std/List[Int]", []int64{4})}
	for _, test := range []struct {
		name, typ   string
		values      []Value
		replacement Value
	}{
		{"Int", "@std/List[Int]", []Value{int64(1), int64(2), int64(3), int64(4)}, int64(99)},
		{"Float", "@std/List[Float]", []Value{1.5, 2.5, 3.5, 4.5}, 99.5},
		{"Bool", "@std/List[Bool]", []Value{false, true, true, false}, false},
		{"String", "@std/List[String]", []Value{"a", "b", "c", "d"}, "changed"},
		{"nested payload", "@std/List[@std/List[Int]]", payloads, NewIntList("@std/List[Int]", []int64{99})},
	} {
		for _, boxed := range []bool{false, true} {
			t.Run(test.name+"/boxed="+Format(boxed), func(t *testing.T) {
				input := NewList(test.typ, test.values)
				if boxed {
					input = &List{Type: test.typ, Items: append([]Value(nil), test.values...)}
				}
				storageKind, elementType := input.kind, typeArguments(input.Type)[0]
				ctx := RootExecution()
				entropy := randomParityZeroEntropy()
				choiceType := "@std/Optional[" + elementType + "]"
				secureChoiceType := "@std/Result[" + choiceType + "][@std/RandomError]"
				chosen := librarySuccess(t, libraryFunctions["random/secure_choice"].Body(ctx, secureChoiceType, []Value{entropy, input})).(Alternative)
				if chosen.Type != choiceType || chosen.Tag != "some" || !Equal(chosen.Fields[0], test.values[0]) {
					t.Fatal("secure choice lost a typed or boxed element", chosen)
				}
				random := &libraryRandom{}
				chosen = libraryFunctions["random/choice"].Body(ctx, choiceType, []Value{random, input}).(Alternative)
				if chosen.Type != choiceType || chosen.Tag != "some" || !Equal(chosen.Fields[0], test.values[3]) || random.state != 0x9e3779b97f4a7c15 {
					t.Fatal("seeded choice changed its first draw or typed payload", chosen)
				}
				shuffled := libraryFunctions["random/shuffle"].Body(ctx, input.Type, []Value{random, input}).(*List)
				if random.state != 0x78dde6e5fd29f054 || shuffled == input || shuffled.Type != input.Type || shuffled.kind != storageKind || shuffled.Len() != 4 {
					t.Fatal("seeded shuffle changed draw count, storage kind or result identity")
				}
				for i, originalIndex := range []int{2, 3, 1, 0} {
					if !Equal(shuffled.Get(i), test.values[originalIndex]) || !Equal(input.Get(i), test.values[i]) {
						t.Fatal("seeded shuffle sequence changed or input was mutated")
					}
				}
				secureShuffleType := "@std/Result[" + input.Type + "][@std/RandomError]"
				secureShuffled := librarySuccess(t, libraryFunctions["random/secure_shuffle"].Body(ctx, secureShuffleType, []Value{entropy, input})).(*List)
				if secureShuffled == input || secureShuffled.Type != input.Type || secureShuffled.kind != storageKind || secureShuffled.Len() != 4 {
					t.Fatal("secure shuffle lost storage kind or result identity")
				}
				for i, originalIndex := range []int{1, 2, 3, 0} {
					if !Equal(secureShuffled.Get(i), test.values[originalIndex]) {
						t.Fatal("secure shuffle changed its Fisher-Yates order")
					}
				}
				if test.name == "nested payload" && (secureShuffled.Get(0) != test.values[1] || shuffled.Get(0) != test.values[2] || chosen.Fields[0] != test.values[3]) {
					t.Fatal("choice or shuffle cloned a shallow payload")
				}
				secureShuffled.Set(0, test.replacement)
				shuffled.Set(0, test.replacement)
				if !Equal(input.Get(1), test.values[1]) || !Equal(input.Get(2), test.values[2]) {
					t.Fatal("shuffle output shares input backing")
				}
				if storageKind != listBoxed && (input.Items != nil || shuffled.Items != nil || secureShuffled.Items != nil) {
					t.Fatal("random operations created boxed mirrors of primitive storage")
				}
				for _, length := range []int{0, 1} {
					trivial := input.CopySlice(0, length)
					before, requests := random.state, len(entropy.requests)
					if length == 0 {
						missing := libraryFunctions["random/choice"].Body(ctx, choiceType, []Value{random, trivial}).(Alternative)
						secureMissing := librarySuccess(t, libraryFunctions["random/secure_choice"].Body(ctx, secureChoiceType, []Value{entropy, trivial})).(Alternative)
						if missing.Tag != "none" || secureMissing.Tag != "none" || missing.Type != choiceType || secureMissing.Type != choiceType {
							t.Fatal("empty choice lost absence or type identity")
						}
					}
					copy := libraryFunctions["random/shuffle"].Body(ctx, input.Type, []Value{random, trivial}).(*List)
					secureCopy := librarySuccess(t, libraryFunctions["random/secure_shuffle"].Body(ctx, secureShuffleType, []Value{entropy, trivial})).(*List)
					if copy == trivial || secureCopy == trivial || copy.Len() != length || secureCopy.Len() != length || copy.kind != storageKind || secureCopy.kind != storageKind || random.state != before || len(entropy.requests) != requests {
						t.Fatal("trivial shuffle/empty choice drew randomness or lost fresh storage")
					}
				}
			})
		}
	}
}

func TestRandomParityChoiceCapturesBeforeEntropyMutation(t *testing.T) {
	for _, kind := range []string{"Int", "Float", "Bool", "String"} {
		for _, boxed := range []bool{false, true} {
			for _, mutation := range []string{"shrink", "reallocate"} {
				typ, original, replacement := "@std/List[Int]", Value(int64(1)), Value(int64(9))
				switch kind {
				case "Float":
					typ, original, replacement = "@std/List[Float]", 1.5, 9.5
				case "Bool":
					typ, original, replacement = "@std/List[Bool]", false, true
				case "String":
					typ, original, replacement = "@std/List[String]", "a", "changed"
				}
				values := []Value{original, original, original, original}
				input := NewList(typ, values)
				if boxed {
					input = &List{Type: typ, Items: append([]Value(nil), values...)}
				}
				want := original
				entropy := &randomParityEntropy{response: func(_ *Execution, count int64) Value {
					if mutation == "reallocate" {
						input.Append(original)
						input.Set(0, replacement)
					} else {
						input.Set(0, replacement)
						input.truncate(0)
						want = replacement
					}
					return libraryOK("@std/Result[@std/Bytes][@std/RandomError]", Bytes{make([]byte, count)})
				}}
				choiceType := "@std/Optional[" + typeArguments(typ)[0] + "]"
				result := "@std/Result[" + choiceType + "][@std/RandomError]"
				got := librarySuccess(t, libraryFunctions["random/secure_choice"].Body(RootExecution(), result, []Value{entropy, input})).(Alternative)
				if got.Tag != "some" || !Equal(got.Fields[0], want) || !reflect.DeepEqual(entropy.requests, []int64{1}) {
					t.Fatalf("%s boxed=%t %s choice read a changed header: %#v, want %v", kind, boxed, mutation, got, want)
				}
			}
		}
	}
}
