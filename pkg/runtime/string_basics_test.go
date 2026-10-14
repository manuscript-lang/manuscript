package msruntime

import (
	"context"
	"strings"
	"testing"
)

// Cancel on the second work check, after a chunk of traversal has run.
// This avoids scheduler timing and detects loops that only check on entry.
type stringWorkCancellation struct {
	context.Context
	cancel context.CancelFunc
	checks int
}

func (ctx *stringWorkCancellation) Err() error {
	ctx.checks++
	if ctx.checks == 2 {
		ctx.cancel()
	}
	return ctx.Context.Err()
}

func TestStringBasicsCancellation(t *testing.T) {
	for _, name := range []string{"length", "is_empty", "chars", "reverse", "compare", "lines"} {
		t.Run(name+" before call", func(t *testing.T) {
			ctx := RootExecution()
			cancelledContext, cancel := context.WithCancel(ctx.Context)
			cancel()
			ctx.Context = cancelledContext
			args := []Argument{}
			if name == "compare" {
				args = append(args, Argument{"other", "text"})
			}
			failure := recovered(func() {
				if name == "length" || name == "is_empty" {
					NativeAccessorRead(ctx, "text", name)
					return
				}
				Invoke(ctx, NativeMemberResult("text", name, ""), args)
			})
			if _, ok := failure.(cancelled); !ok {
				t.Fatalf("cancelled String.%s became %#v", name, failure)
			}
		})
	}
	for _, name := range []string{"chars", "reverse", "lines"} {
		t.Run(name+" during traversal", func(t *testing.T) {
			ctx := RootExecution()
			workContext, cancel := context.WithCancel(context.Background())
			defer cancel()
			work := &stringWorkCancellation{Context: workContext, cancel: cancel}
			ctx.Context = work
			spec, ok := NativeLibrarySpec("String", name)
			if !ok {
				t.Fatal("missing native String method", name)
			}
			failure := recovered(func() { spec.Body(ctx, libraryRuntimeType(spec.Result), []Value{strings.Repeat("é🙂\r\n", 4096)}) })
			if _, ok := failure.(cancelled); !ok || work.checks < 2 {
				t.Fatalf("String.%s did not cancel during work: %#v (%d checks)", name, failure, work.checks)
			}
		})
	}
}
