package msruntime

import (
	"testing"
	"time"
)

func TestRunnerFiltersAndTimesOutByName(t *testing.T) {
	ran := map[string]bool{}
	pass := func(name string) Test {
		return Test{name, NewFunction(nil, "Unit", func(*Execution, []Value) Value { ran[name] = true; return Unit{} })}
	}
	stuck := Test{"m.ms::stuck", NewFunction(nil, "Unit", func(ctx *Execution, _ []Value) Value {
		<-ctx.Context.Done()
		CheckCancelled(ctx)
		return Unit{}
	})}
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

func TestParseTestArgs(t *testing.T) {
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
