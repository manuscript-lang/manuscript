package lsp

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestHTTPRequestHeaderNavigation(t *testing.T) {
	source := `import HttpRequest from "@std/http.ms"
import Bytes from "@std/bytes.ms"
fn content_type(request: HttpRequest) -> Optional[Bytes]:
    return request.header("content-type")
`
	file, _, hover := definitionAt(t, source, strings.Index(source, "header("))
	if file != "@std/http.ms" || !strings.Contains(hover, "fn(name: String)->Optional[Bytes]") {
		t.Fatalf("header navigation: %s %q", file, hover)
	}
}

func TestLocalHTTPRequestDoesNotAcquireNativeHeader(t *testing.T) {
	source := `type HttpRequest:
    value: String
fn lookup(request: HttpRequest) -> Unit:
    request.header("content-type")
`
	result := compiler.CompileSource("local-header.ms", source, compiler.Options{AnalyzeOnly: true})
	if result.Success() {
		t.Fatal("local record acquired native header")
	}
	found := false
	for _, diagnostic := range result.Diagnostics {
		found = found || strings.Contains(diagnostic.Message, "unknown or ambiguous member header")
	}
	if !found {
		t.Fatal(result.Diagnostics)
	}
}
