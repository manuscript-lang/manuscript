package msruntime

import (
	"os"
	"os/exec"
	"testing"
)

// A subprocess gives the monotonic process concurrency flag its real initial
// state, independent of other tests that already started source work.
func TestRecordConcurrencyStartsWithSourceWork(t *testing.T) {
	if os.Getenv("MANUSCRIPT_RECORD_STARTUP_TEST") != "1" {
		command := exec.Command(os.Args[0], "-test.run=^TestRecordConcurrencyStartsWithSourceWork$")
		command.Env = append(os.Environ(), "MANUSCRIPT_RECORD_STARTUP_TEST=1")
		if out, err := command.CombinedOutput(); err != nil {
			t.Fatalf("startup: %v\n%s", err, out)
		}
		return
	}
	if concurrentWork.Load() {
		t.Fatal("process starts concurrent")
	}
	main := NewSourceFunction(nil, "Int", "startup.ms:1", func(ctx *Execution, _ []Value) Value {
		if concurrentWork.Load() {
			t.Fatal("signal handler marked user records concurrent")
		}
		record := Record{Type: "Counter", Fields: map[string]Value{"value": int64(0)}}
		group := NewTaskGroup(ctx, nil).(*TaskGroup)
		defer group.close(ctx)
		for range 4 {
			groupTask(ctx, group, NewSourceFunction(nil, "Unit", "worker.ms:1", func(_ *Execution, _ []Value) Value {
				if !concurrentWork.Load() {
					panic("worker admitted without record locks")
				}
				for i := range 2000 {
					SetField(record, "value", int64(i))
					_ = Field(record, "value")
					_ = fieldsCopy(record.Fields)
				}
				return Unit{}
			}))
		}
		if outcome := groupResult(ctx, group); outcome.Tag != "ok" {
			t.Fatal(outcome)
		}
		if !concurrentWork.Load() {
			t.Fatal("source work did not mark concurrency")
		}
		return int64(0)
	})
	if exit := RunMain(main, nil); exit != 0 {
		t.Fatal(exit)
	}
}
