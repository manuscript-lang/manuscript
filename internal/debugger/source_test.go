package debugger

import (
	"math/rand"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSourceLinePreservesText(t *testing.T) {
	names := Names{Root: t.TempDir()}
	path := filepath.Join(names.Root, "main.ms")
	texts := []string{
		"", "\n", "\n\n", "first\nlast", "first\nlast\n",
		"first\r\n\r\nlast\r\r\n", "embedded\rcarriage\r\r",
		"nul\x00byte\ninvalid\xff\xfe\r\nUnicode 日本語",
		strings.Repeat("long line ", 128*1024) + "\r\r\nlast",
	}
	// Compare the original Split contract over arbitrary bytes, including line
	// delimiters and repeated CRs, rather than assuming valid UTF-8 source.
	random := rand.New(rand.NewSource(1))
	for i := 0; i < 100; i++ {
		data := make([]byte, random.Intn(128))
		for j := range data {
			data[j] = []byte{'x', '\n', '\r', 0, 0xff}[random.Intn(5)]
		}
		texts = append(texts, string(data))
	}
	for fixture, text := range texts {
		if err := os.WriteFile(path, []byte(text), 0600); err != nil {
			t.Fatal(err)
		}
		lines := strings.Split(text, "\n")
		for line := -1; line <= len(lines)+1; line++ {
			want := ""
			if line >= 1 && line <= len(lines) {
				want = strings.TrimRight(lines[line-1], "\r")
			}
			if got := names.sourceLine("main.ms", line); got != want {
				t.Fatalf("fixture %d, line %d: got %q, want %q", fixture, line, got, want)
			}
		}
	}
}

func TestSourceLineReadsCurrentFile(t *testing.T) {
	names := Names{Root: t.TempDir()}
	path := filepath.Join(names.Root, "main.ms")
	for _, text := range []string{"first\nold", "first\nupdated", "shorter"} {
		if err := os.WriteFile(path, []byte(text), 0600); err != nil {
			t.Fatal(err)
		}
		want := ""
		if lines := strings.Split(text, "\n"); len(lines) > 1 {
			want = lines[1]
		}
		if got := names.sourceLine("main.ms", 2); got != want {
			t.Fatalf("changed source: got %q, want %q", got, want)
		}
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if got := names.sourceLine("main.ms", 1); got != "" {
		t.Fatalf("deleted source: got %q", got)
	}
	if got := names.sourceLine(".", 1); got != "" {
		t.Fatalf("unreadable source directory: got %q", got)
	}
}
