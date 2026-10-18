package compiler

import (
	"fmt"
	"strings"
	"testing"
)

func TestCompressionDefaultCallableBoundaries(t *testing.T) {
	const imports = `import {compress, CompressionFormat, CompressionError} from "@std/compress.ms"
import Bytes from "@std/bytes.ms"
fn forward[T](item: T) T: item
`
	for _, item := range []struct{ name, body, want string }{
		{"required format", `compress("".to_bytes())`, "missing argument format"},
		{"required data", `CompressionFormat.Gzip.compress()`, "missing argument data"},
		{"wrong free level", `compress("".to_bytes(), "gzip", level: none)`, "expected Int"},
		{"wrong bound level", `CompressionFormat.Gzip.compress("".to_bytes(), level: none)`, "expected Int"},
		{"mutable free", "var encode = compress\n    encode(\"\".to_bytes(), \"gzip\")", "missing argument level"},
		{"forwarded free", "let encode = forward(compress)\n    encode(\"\".to_bytes(), \"gzip\")", "missing argument level"},
		{"typed free", "let encode: fn(data: Bytes, format: String, level: Int, max_bytes: Optional[Int]) Result[Bytes, CompressionError] = compress\n    encode(\"\".to_bytes(), \"gzip\")", "missing argument level"},
		{"mutable bound", "var encode = CompressionFormat.Gzip.compress\n    encode(\"\".to_bytes())", "missing argument level"},
		{"forwarded bound", "let encode = forward(CompressionFormat.Gzip.compress)\n    encode(\"\".to_bytes())", "missing argument level"},
		{"typed bound", "let encode: fn(data: Bytes, level: Int, max_bytes: Optional[Int]) Result[Bytes, CompressionError] = CompressionFormat.Gzip.compress\n    encode(\"\".to_bytes())", "missing argument level"},
	} {
		t.Run(item.name, func(t *testing.T) {
			r := CompileSource("compression-boundary.ms", imports+"fn check() Unit:\n    "+item.body+"\n", Options{AnalyzeOnly: true})
			if r.Success() || !strings.Contains(fmt.Sprint(r.Diagnostics), item.want) {
				t.Fatalf("want %q: %v", item.want, r.Diagnostics)
			}
		})
	}
}

func TestCompressionExplicitLevelsKeepDirectDispatch(t *testing.T) {
	r := CompileSource("explicit-compression.ms", `import {compress, CompressionFormat} from "@std/compress.ms"
fn explicit() Unit:
    let data = "".to_bytes()
    compress(data, "gzip", 6)
    compress(data, "zlib", 0, max_bytes: none)
    compress(data, "deflate", 9, max_bytes: 100)
    CompressionFormat.Gzip.compress(data, 6)
    CompressionFormat.Zlib.compress(data, 0, max_bytes: none)
    CompressionFormat.Deflate.compress(data, 9, max_bytes: 100)
`, Options{})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if strings.Contains(r.Source, "WithDefaults") || strings.Contains(r.Source, "PreparedDefaults") {
		t.Fatal("explicit compression levels emitted default preparation")
	}
}
