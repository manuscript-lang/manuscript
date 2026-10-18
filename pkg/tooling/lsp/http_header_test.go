package lsp

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestHTTPRequestHeaderNavigation(t *testing.T) {
	source := `import HttpRequest from "@std/http.ms"
import Bytes from "@std/bytes.ms"
fn content_type(request: HttpRequest) Optional[List[Bytes]]:
    return request.headers.values("content-type")
`
	file, _, hover := definitionAt(t, source, strings.Index(source, "values("))
	if file != "@std/http.ms" || !strings.Contains(hover, "fn(name: String) Optional[List[Bytes]]") {
		t.Fatalf("header navigation: %s %q", file, hover)
	}
}

func TestLocalHttpHeadersDoesNotAcquireNativeLookup(t *testing.T) {
	source := `type HttpHeaders:
    value: String
fn lookup(fields: HttpHeaders) Unit:
    fields.values("content-type")
`
	result := compiler.CompileSource("local-header.ms", source, compiler.Options{AnalyzeOnly: true})
	if result.Success() {
		t.Fatal("local record acquired native header lookup")
	}
	found := false
	for _, diagnostic := range result.Diagnostics {
		found = found || strings.Contains(diagnostic.Message, "unknown or ambiguous member values")
	}
	if !found {
		t.Fatal(result.Diagnostics)
	}
}
