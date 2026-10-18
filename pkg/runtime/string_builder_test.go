package msruntime

import (
	"context"
	"runtime"
	"strings"
	"testing"
)

func TestStringBuilderAliasesAndFrozenLifetime(t *testing.T) {
	b := NewStringBuilder()
	alias := b
	for i := 0; i < 1000; i++ {
		StringBuilder_Append(tctx, alias, "aé日")
	}
	frozen := StringBuilder_Freeze(tctx, b)
	if frozen != strings.Repeat("aé日", 1000) || StringBuilder_Freeze(tctx, alias) != frozen {
		t.Fatal("aliases lost accumulated text")
	}
	if got := faultMessage(func() { StringBuilder_Append(tctx, alias, "") }); got != "builder is sealed" {
		t.Fatalf("empty append through sealed alias: %q", got)
	}
	b, alias = nil, nil
	runtime.GC()
	if frozen != strings.Repeat("aé日", 1000) {
		t.Fatal("frozen backing did not survive its builder")
	}
}

func TestStringBuilderEmptyAndCancelledFreeze(t *testing.T) {
	b := NewStringBuilder()
	first := StringBuilder_Freeze(tctx, b)
	if first != "" || StringBuilder_Freeze(tctx, b) != first {
		t.Fatal("empty freeze")
	}
	if got := faultMessage(func() { StringBuilder_Append(tctx, b, "x") }); got != "builder is sealed" {
		t.Fatalf("empty builder was not sealed: %q", got)
	}
	b = NewStringBuilder()
	cancelledContext, cancel := context.WithCancel(context.Background())
	cancel()
	func() {
		defer func() {
			if _, ok := recover().(cancelled); !ok {
				t.Fatal("freeze did not observe cancellation")
			}
		}()
		StringBuilder_Freeze(&Execution{Context: cancelledContext}, b)
	}()
	StringBuilder_Append(tctx, b, "still open")
	if StringBuilder_Freeze(tctx, b) != "still open" {
		t.Fatal("cancelled freeze sealed the builder")
	}
}

func BenchmarkStringBuilderVsGo(b *testing.B) {
	b.Run("Manuscript", func(b *testing.B) {
		b.ReportAllocs()
		for n := 0; n < b.N; n++ {
			builder := NewStringBuilder()
			for i := 0; i < 50000; i++ {
				StringBuilder_Append(tctx, builder, "x")
			}
			if len(StringBuilder_Freeze(tctx, builder)) != 50000 {
				b.Fatal("incorrect length")
			}
		}
	})
	b.Run("Go", func(b *testing.B) {
		b.ReportAllocs()
		for n := 0; n < b.N; n++ {
			var builder strings.Builder
			for i := 0; i < 50000; i++ {
				builder.WriteString("x")
			}
			if len(builder.String()) != 50000 {
				b.Fatal("incorrect length")
			}
		}
	})
}
