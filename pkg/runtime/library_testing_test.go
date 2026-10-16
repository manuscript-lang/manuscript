package msruntime

import (
	"math"
	"strings"
	"testing"
)

func testEqInt(_ *Execution, a, b int) bool { return a == b }

func failureOf[T any](ctx *Execution, outcome Result[T, Error]) string {
	if !outcome.Failed {
		return ""
	}
	return outcome.Err.Message(ctx)
}

func TestTestingAssertionsReturnErrors(t *testing.T) {
	ctx := RootExecution()
	if got := failureOf(ctx, Testing_ExpectEqual(ctx, testEqInt, 1, 1)); got != "" {
		t.Fatalf("equal failed: %q", got)
	}
	if got := failureOf(ctx, Testing_ExpectClose(ctx, math.Inf(1), math.Inf(1), 0)); got != "" {
		t.Fatalf("close failed: %q", got)
	}
	for _, args := range [][3]float64{{math.NaN(), 1, 0.1}, {1, 1, -0.1}, {1, 1, math.Inf(1)}} {
		if failureOf(ctx, Testing_ExpectClose(ctx, args[0], args[1], args[2])) == "" {
			t.Fatalf("accepted close %v", args)
		}
	}
	if got := failureOf(ctx, Testing_ExpectEqual(ctx, testEqInt, 1, 2)); got != "expected 2, got 1" {
		t.Fatalf("message %q", got)
	}
	if got := failureOf(ctx, Testing_Fail(ctx, "no")); got != "no" {
		t.Fatalf("fail message %q", got)
	}
	if got := failureOf(ctx, Testing_ExpectSome(ctx, None[int]())); got != "expected some, got none" {
		t.Fatalf("some message %q", got)
	}
	if got := Testing_ExpectFault(ctx, func(c *Execution) Unit { Raise("boom"); return Unit{} }); got.Failed || got.Val != "boom" {
		t.Fatalf("fault message %+v", got)
	}
	if got := failureOf(ctx, Testing_ExpectFault(ctx, func(*Execution) Unit { return Unit{} })); !strings.Contains(got, "returned normally") {
		t.Fatalf("message %q", got)
	}
	for _, failure := range []any{testSkip{"reason"}, cancelled{}} {
		func() {
			defer func() {
				if got := recover(); got != failure {
					t.Fatalf("fault assertion swallowed %T: %v", failure, got)
				}
			}()
			Testing_ExpectFault(ctx, func(*Execution) Unit { panic(failure) })
		}()
	}
}

func TestTestingFormatsLoweredValues(t *testing.T) {
	ctx := RootExecution()
	cases := map[string]any{
		`"bad"`:             "bad",
		"some(7)":           Some(int(7)),
		"none":              None[int](),
		"ok(9)":             Ok[int, string](9),
		`error("bad")`:      Fail[int, string]("bad"),
		"[1, 2]":            NewList[int](1, 2),
		"Text(text: \"a\")": TerminalEvent_Text{Text: "a"},
	}
	for want, value := range cases {
		if got := testFormat(value); got != want {
			t.Errorf("format %v: got %q want %q", value, got, want)
		}
	}
	_ = ctx
}
