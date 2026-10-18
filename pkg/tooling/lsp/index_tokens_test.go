package lsp

import (
	"fmt"
	"reflect"
	"sync"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestPinnedIndexTokensMatchLexer(t *testing.T) {
	modules := checker.StandardModules()
	for _, m := range modules {
		t.Run(m.File, func(t *testing.T) {
			want, wantErr := lexer.Lex(m.File, m.Source)
			got, err := indexTokens(m)
			if err != nil || wantErr != nil || !reflect.DeepEqual(got, want) {
				t.Fatalf("pinned token positions/text differ: cached error %v, lexer error %v", err, wantErr)
			}
			again, err := indexTokens(m)
			if err != nil || len(got) == 0 || &got[0] != &again[0] {
				t.Fatal("unchanged pinned source did not reuse its immutable tokens")
			}
		})
	}
	if got := len(pinnedIndexTokens()); got != len(modules) {
		t.Fatalf("inventory has %d files, pinned modules have %d", got, len(modules))
	}
}

func TestPinnedIndexTokensRequireExactInput(t *testing.T) {
	m := checker.StandardModules()[0]
	wantPinned, err := indexTokens(m)
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct{ file, source string }{
		{m.File, "export fn changed() Int:\n    return 7\n"},
		{m.File, "export fn broken(\n"},
		{"@std/unknown.ms", "export fn different() Int:\n    return 9\n"},
		{"/workspace/" + m.File, m.Source},
	} {
		got, gotErr := indexTokens(&syntax.Module{File: tc.file, Source: tc.source})
		want, wantErr := lexer.Lex(tc.file, tc.source)
		if !reflect.DeepEqual(got, want) || fmt.Sprint(gotErr) != fmt.Sprint(wantErr) {
			t.Fatalf("fallback changed for %q: errors %v / %v", tc.file, gotErr, wantErr)
		}
	}
	for i := range 100 {
		_, _ = indexTokens(&syntax.Module{File: fmt.Sprintf("@std/unknown-%d.ms", i), Source: "let arbitrary = 1\n"})
	}
	if got := len(pinnedIndexTokens()); got != len(checker.StandardModules()) {
		t.Fatalf("arbitrary inputs grew pinned inventory to %d files", got)
	}
	again, err := indexTokens(m)
	if err != nil || !reflect.DeepEqual(again, wantPinned) || &again[0] != &wantPinned[0] {
		t.Fatal("fallback input poisoned pinned tokens")
	}
}

func TestPinnedIndexTokensConcurrentFirstUse(t *testing.T) {
	// In a fresh -run process these goroutines contend on both inventory and
	// token initialization. No test resets the published process-wide cache.
	modules := checker.StandardModules()
	var wg sync.WaitGroup
	for range 8 {
		wg.Go(func() {
			for _, m := range modules {
				got, err := indexTokens(m)
				want, wantErr := lexer.Lex(m.File, m.Source)
				if err != nil || wantErr != nil || !reflect.DeepEqual(got, want) {
					t.Errorf("concurrent pinned tokens differ for %s: %v / %v", m.File, err, wantErr)
				}
			}
		})
	}
	wg.Wait()
}
