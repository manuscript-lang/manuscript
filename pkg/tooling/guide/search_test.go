package guide

import (
	"strings"
	"testing"
)

func TestSearchFindsAPIsFromLooseQueries(t *testing.T) {
	cases := []struct{ query, module, name string }{
		{"jsn parse", "@std/json.ms", "parse"},
		{"read file", "@std/fs.ms", "FileSystem.read_file"},
		{"JSON PARSE", "@std/json.ms", "parse"},
		{"http server", "@std/http.ms", "HttpServer"},
		{"parse_int", "@std/numbers.ms", "parse_int"},
		{"sleep", "@std/time.ms", "sleep"},
		{"regex replace", "@std/regex.ms", "Regex.replace_all"},
		{"base64 encode", "@std/encoding.ms", "base64_encode"},
		{"sorted", "prelude", "List.sorted"},
		{"sort by", "prelude", "List.sorted"},
		{"read stdin lines", "@std/io.ms", "read_line"},
		{"uppercase", "prelude", "String.upper"},
	}
	for _, c := range cases {
		matches := Search(c.query, 3)
		found := false
		for _, m := range matches {
			found = found || m.Module == c.module && m.Name == c.name
		}
		if !found {
			t.Errorf("Search(%q) top 3 = %v, want %s %s", c.query, summaries(matches), c.module, c.name)
		}
	}
}

func TestSearchExactNameOutranksFuzzyNames(t *testing.T) {
	matches := Search("sleep", 5)
	if len(matches) == 0 || matches[0].Name != "sleep" {
		t.Fatalf("Search(sleep) = %v", summaries(matches))
	}
}

func TestSearchIsStableAndBounded(t *testing.T) {
	a, b := Search("list", 5), Search("list", 5)
	if len(a) != 5 || len(a) != len(b) {
		t.Fatalf("lengths %d %d", len(a), len(b))
	}
	for i := range a {
		if a[i].Module != b[i].Module || a[i].Name != b[i].Name {
			t.Fatalf("unstable order at %d: %v vs %v", i, a[i], b[i])
		}
	}
	seen := map[string]bool{}
	for _, m := range Search("sorted", 25) {
		key := m.Name + m.Signature
		if seen[key] {
			t.Errorf("duplicate declaration %s from %s", m.Name, m.Module)
		}
		seen[key] = true
	}
}

func TestSearchRejectsNoiseAndEmptyQueries(t *testing.T) {
	if got := Search("   ", 5); got != nil {
		t.Errorf("blank query matched %v", got)
	}
	partial := Search("split zzqxjv", 3)
	if len(partial) == 0 || partial[0].Name != "String.split" {
		t.Errorf("partial query = %v", summaries(partial))
	}
	if got := Search("zzqxjv", 5); len(got) != 0 {
		t.Errorf("nonsense matched %v", summaries(got))
	}
	if text := FormatMatches("zzqxjv", nil); !strings.Contains(text, "No standard-library match") {
		t.Errorf("empty message: %q", text)
	}
}

func summaries(matches []Match) []string {
	var out []string
	for _, m := range matches {
		out = append(out, m.Module+" "+m.Name)
	}
	return out
}
