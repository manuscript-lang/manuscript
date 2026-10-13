package msruntime

import (
	"context"
	"regexp"
	"strings"
	"testing"
)

func TestRegexSplitMatchesNativeZeroWidthRulesAndTruncation(t *testing.T) {
	ctx := RootExecution()
	for _, pattern := range []string{"", ",", "(,)", "^", "$", "a*", "a+", "b?", ".*"} {
		compiled := regexp.MustCompile(pattern)
		for _, input := range []string{"", "a", "abc", ",a,,b,", "é🙂é", "a\nb"} {
			whole := compiled.Split(input, -1)
			for _, limit := range []int64{0, 1, 2, 3, nativeUnlimited} {
				want := whole
				if limit < int64(len(want)) {
					want = want[:limit]
				}
				value := libraryRegexSplit(ctx, "@std/Result[@std/List[String]][@std/RegexError]", []Value{libraryRegex{compiled}, input, limit}).(Alternative)
				got := libraryStringValues(value.Fields[0])
				if len(got) != len(want) || strings.Join(got, "\x00") != strings.Join(want, "\x00") {
					t.Errorf("pattern %q input %q cap %d: got %#v want %#v", pattern, input, limit, got, want)
				}
			}
		}
	}
}

func TestTextParityCancellationAndInvalidOffsets(t *testing.T) {
	for _, start := range []int64{-1, 4} {
		failure := recovered(func() {
			Invoke(RootExecution(), NativeMemberResult(Bytes{[]byte("abc")}, "index_of_from", ""), []Argument{{"value", Bytes{}}, {"start", start}})
		})
		if fault, ok := failure.(Fault); !ok || !strings.Contains(fault.Message, "Bytes.index_of_from: start must be between 0 and 3") {
			t.Fatalf("unexpected offset failure %#v", failure)
		}
	}
	for _, call := range []func(*Execution){
		func(ctx *Execution) { libraryRegexFind(ctx, "", []Value{libraryRegex{regexp.MustCompile("x")}, "x"}) },
		func(ctx *Execution) {
			libraryRegexSplit(ctx, "@std/Result[@std/List[String]][@std/RegexError]", []Value{libraryRegex{regexp.MustCompile(",")}, "a,b", int64(0)})
		},
		func(ctx *Execution) { Invoke(ctx, NativeMemberResult(Bytes{}, "to_hex", ""), nil) },
		func(ctx *Execution) {
			Invoke(ctx, NativeMemberResult(Bytes{}, "index_of_from", ""), []Argument{{"value", Bytes{}}, {"start", int64(0)}})
		},
	} {
		ctx := RootExecution()
		cancelledContext, cancel := context.WithCancel(ctx.Context)
		cancel()
		ctx.Context = cancelledContext
		if failure := recovered(func() { call(ctx) }); failure == nil {
			t.Fatal("cancelled operation returned")
		} else if _, ok := failure.(cancelled); !ok {
			t.Fatalf("cancellation became %#v", failure)
		}
	}
	ctx := RootExecution()
	workContext, cancel := context.WithCancel(ctx.Context)
	defer cancel()
	ctx.Context = &stringWorkCancellation{Context: workContext, cancel: cancel}
	if failure := recovered(func() {
		libraryRegexFind(ctx, "", []Value{libraryRegex{regexp.MustCompile("z")}, strings.Repeat("é", 4096) + "z"})
	}); failure == nil {
		t.Fatal("regex find lost post-engine cancellation")
	}
}
