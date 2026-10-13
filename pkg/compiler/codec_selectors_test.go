package compiler

import (
	"strings"
	"testing"
)

func TestTypedCodecSelectorsRejectInvalidCasesAndTypes(t *testing.T) {
	for _, test := range []struct{ name, source, want string }{
		{"algorithm typo", `import HashAlgorithm from "@std/crypto.ms"
fn wrong() -> Unit:
    let algorithm = HashAlgorithm.Sha257
`, "Sha257"},
		{"compression typo", `import CompressionFormat from "@std/compress.ms"
fn wrong() -> Unit:
    let format = CompressionFormat.GZip
`, "GZip"},
		{"archive typo", `import ArchiveFormat from "@std/archive.ms"
fn wrong() -> Unit:
    let format = ArchiveFormat.TAR
`, "TAR"},
		{"string into typed selector", `import HashAlgorithm from "@std/crypto.ms"
fn choose(algorithm: HashAlgorithm) -> Unit:
    return unit
fn wrong() -> Unit:
    choose("sha256")
`, "HashAlgorithm"},
		{"wrong selector family", `import HashAlgorithm from "@std/crypto.ms"
import CompressionFormat from "@std/compress.ms"
fn choose(algorithm: HashAlgorithm) -> Unit:
    return unit
fn wrong() -> Unit:
    choose(CompressionFormat.Gzip)
`, "HashAlgorithm"},
	} {
		t.Run(test.name, func(t *testing.T) {
			result := CompileSource("codec-type.ms", test.source, Options{AnalyzeOnly: true})
			if result.Success() {
				t.Fatal("invalid selector compiled")
			}
			text := ""
			for _, diagnostic := range result.Diagnostics {
				text += diagnostic.Message + "\n"
			}
			if !strings.Contains(text, test.want) {
				t.Fatalf("missing selector diagnostic: %s", text)
			}
		})
	}
}
