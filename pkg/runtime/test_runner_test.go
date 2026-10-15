package msruntime

import (
	"testing"
	"time"
)

func TestRunnerFiltersAndTimesOutByName(t *testing.T) {
	ran := map[string]bool{}
	pass := func(name string) Test {
		return Test{Name: name, Run: func(*Execution) Unit { ran[name] = true; return Unit{} }}
	}
	stuck := Test{Name: "m.ms::stuck", Run: func(ctx *Execution) Unit {
		<-ctx.Context.Done()
		return CheckCancelled(ctx)
	}}
	tests := []Test{pass("m.ms::quick"), stuck, pass("m.ms::after")}
	if failed := RunTestsWith(tests, TestOptions{Timeout: 50 * time.Millisecond}); failed != 1 || !ran["m.ms::after"] {
		t.Fatalf("failed=%d ran=%v, want only the stuck test to fail and later tests to run", failed, ran)
	}
	ran = map[string]bool{}
	if failed := RunTestsWith(tests, TestOptions{Filter: "after"}); failed != 0 || len(ran) != 1 || !ran["m.ms::after"] {
		t.Fatalf("filter: failed=%d ran=%v", failed, ran)
	}
	if failed := RunTestsWith(tests, TestOptions{Filter: "nothing"}); failed != 1 {
		t.Fatalf("unmatched filter must fail, got %d", failed)
	}
}

func TestParseTestArgsSelection(t *testing.T) {
	options, err := ParseTestArgs([]string{"--timeout=2s", "--filter=a b", "other"})
	if err != nil || options.Timeout != 2*time.Second || options.Filter != "a b" {
		t.Fatalf("%+v, %v", options, err)
	}
	if options, _ := ParseTestArgs(nil); options.Timeout != DefaultTestTimeout {
		t.Fatalf("default timeout %v", options.Timeout)
	}
	if _, err := ParseTestArgs([]string{"--timeout=soon"}); err == nil {
		t.Fatal("invalid timeout accepted")
	}
}

func TestRunnerSelectionRepeatListAndFailFast(t *testing.T) {
	var ran []string
	tests := []Test{}
	for _, name := range []string{"a::one", "a::two", "b::three"} {
		tests = append(tests, Test{Name: name, Run: func(*Execution) Unit { ran = append(ran, name); return Unit{} }})
	}
	options, err := ParseTestArgs([]string{"--match=^a::", "--exclude=two", "--repeat=2", "--shuffle=42"})
	if err != nil {
		t.Fatal(err)
	}
	if status := RunTestsWith(tests, options); status != 0 || len(ran) != 2 || ran[0] != "a::one" {
		t.Fatalf("status %d ran %v", status, ran)
	}
	ran = nil
	if RunTestsWith(tests, TestOptions{Names: []string{"a::two"}, List: true}) != 0 || len(ran) != 0 {
		t.Fatal("list executed tests")
	}
	if RunTestsWith(tests, TestOptions{Names: []string{"missing"}}) == 0 {
		t.Fatal("unknown exact name accepted")
	}
	tests[0].Run = func(*Execution) Unit { return Panic(nil, "failed") }
	if RunTestsWith(tests, TestOptions{FailFast: true}) != 1 || len(ran) != 0 {
		t.Fatalf("fail fast ran %v", ran)
	}
	for _, args := range [][]string{{"--match=["}, {"--exclude=["}, {"--repeat=0"}, {"--repeat=-1"}, {"--shuffle=no"}} {
		if _, err := ParseTestArgs(args); err == nil {
			t.Fatalf("accepted %v", args)
		}
	}
}

func TestRunnerShuffleIsReproducible(t *testing.T) {
	run := func(seed int64) []string {
		var ran []string
		tests := make([]Test, 10)
		for i := range tests {
			name := string(rune('a' + i))
			tests[i] = Test{Name: name, Run: func(*Execution) Unit { ran = append(ran, name); return Unit{} }}
		}
		RunTestsWith(tests, TestOptions{Shuffle: true, Seed: seed})
		return ran
	}
	a, b := run(17), run(17)
	for i := range a {
		if a[i] != b[i] {
			t.Fatalf("different order %v %v", a, b)
		}
	}
}
