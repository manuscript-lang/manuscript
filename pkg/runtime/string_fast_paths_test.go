package msruntime

import (
	"testing"

	"golang.org/x/text/cases"
	"golang.org/x/text/language"
)

// The ASCII and substring fast paths must agree with the general paths.
func TestStringFastPathsMatchGeneralPaths(t *testing.T) {
	for _, text := range []string{"", "plain ascii MiXed 123", "héllo wörld ✓ ǅ", "ß straße İ", "a\xffb", "é\xc3", "日本語 text"} {
		if got, want := String_Upper(tctx, text), cases.Upper(language.Und).String(text); got != want {
			t.Errorf("upper(%q) = %q, want %q", text, got, want)
		}
		if got, want := String_Lower(tctx, text), cases.Lower(language.Und).String(text); got != want {
			t.Errorf("lower(%q) = %q, want %q", text, got, want)
		}
		var scalars []string
		for _, r := range text {
			scalars = append(scalars, string(r))
		}
		chars := String_Chars(tctx, text).Items
		if len(chars) != len(scalars) {
			t.Fatalf("chars(%q) = %q, want %q", text, chars, scalars)
		}
		for i := range scalars {
			if chars[i] != scalars[i] {
				t.Errorf("chars(%q)[%d] = %q, want %q", text, i, chars[i], scalars[i])
			}
			if at := String_Get(tctx, text, i, Some("?")); at != scalars[i] {
				t.Errorf("at(%q, %d) = %v, want %q", text, i, at, scalars[i])
			}
			if at := String_Get(tctx, text, i-len(scalars), Some("?")); at != scalars[i] {
				t.Errorf("at(%q, %d) = %v, want %q", text, i-len(scalars), at, scalars[i])
			}
		}
		if String_Get(tctx, text, len(scalars), Some("?")) != "?" || String_Get(tctx, text, -len(scalars)-1, Some("?")) != "?" {
			t.Errorf("at(%q) accepted an out-of-range index", text)
		}
	}
}

// Entries are stored by value: a snapshot keeps the values it was taken with.
func TestMapSnapshotIsStableAcrossReplaceAndDelete(t *testing.T) {
	m := NewMap[string, int]()
	for i, k := range []string{"a", "b", "c"} {
		m.Put(k, i)
	}
	snapshot := m.Snapshot()
	m.Put("a", 10)
	m.Delete("b")
	m.Put("d", 3)
	want := []MapEntry[string, int]{{"a", 0}, {"b", 1}, {"c", 2}}
	if len(snapshot) != len(want) {
		t.Fatalf("snapshot = %v", snapshot)
	}
	for i, e := range snapshot {
		if *e != want[i] {
			t.Errorf("snapshot[%d] = %v, want %v", i, *e, want[i])
		}
	}
	live := m.Snapshot()
	if len(live) != 3 || *live[0] != (MapEntry[string, int]{"a", 10}) || *live[1] != (MapEntry[string, int]{"c", 2}) || *live[2] != (MapEntry[string, int]{"d", 3}) {
		t.Errorf("live = %v %v %v", live[0], live[1], live[2])
	}
}
