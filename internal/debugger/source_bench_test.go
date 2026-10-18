package debugger

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

var sourceLineResult string

// Exercise the actual stop-event source lookup, including the fresh file read.
// Fixtures are created before timing and remain in the filesystem cache.
func BenchmarkSourceLine(b *testing.B) {
	for _, fixture := range []struct {
		name string
		text string
		line int
	}{
		{"tiny_first", "fn main():\n    let value = 42\n    print(value)\n", 1},
		{"tiny_last", "fn main():\n    let value = 42\n    print(value)\n", 3},
		{"1000_middle", strings.Repeat("    let value = 42 # source statement\n", 1000), 500},
		{"100000_first", strings.Repeat("    let value = 42 # source statement\n", 100000), 1},
		{"100000_middle", strings.Repeat("    let value = 42 # source statement\n", 100000), 50000},
		{"100000_last", strings.Repeat("    let value = 42 # source statement\n", 100000), 100000},
		{"long_line", strings.Repeat("x", 1024*1024) + "\r\n", 1},
		{"dense_blank_lines", strings.Repeat("\n", 100000), 50000},
		{"past_eof", strings.Repeat("    let value = 42 # source statement\n", 100000), 100002},
	} {
		b.Run(fixture.name, func(b *testing.B) {
			names := Names{Root: b.TempDir()}
			if err := os.WriteFile(filepath.Join(names.Root, "main.ms"), []byte(fixture.text), 0600); err != nil {
				b.Fatal(err)
			}
			want := ""
			if lines := strings.Split(fixture.text, "\n"); fixture.line <= len(lines) {
				want = strings.TrimRight(lines[fixture.line-1], "\r")
			}
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				sourceLineResult = names.sourceLine("main.ms", fixture.line)
			}
			b.StopTimer()
			if sourceLineResult != want {
				b.Fatal("source line changed")
			}
		})
	}
	b.Run("missing_file_control", func(b *testing.B) {
		names := Names{Root: b.TempDir()}
		b.ReportAllocs()
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			sourceLineResult = names.sourceLine("missing.ms", 1)
		}
		b.StopTimer()
		if sourceLineResult != "" {
			b.Fatal("missing file should have no source line")
		}
	})
}

// Unchanged source mapping is a scaling and negative control for sourceLine.
func BenchmarkNamesFunction(b *testing.B) {
	for _, count := range []int{10, 1000, 100000} {
		b.Run(fmt.Sprint(count), func(b *testing.B) {
			names := Names{Root: "/work"}
			for i := 0; i < count; i++ {
				names.Entities = append(names.Entities, Entity{Name: "helper", File: "main.ms", Line: i*10 + 1, Function: true})
			}
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				sourceLineResult = names.function("/work/main.ms", count*5)
			}
			b.StopTimer()
			if sourceLineResult != "helper" {
				b.Fatal("function lookup changed")
			}
		})
	}
}
