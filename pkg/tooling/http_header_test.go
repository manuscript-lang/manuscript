package tooling_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

func TestHTTPRequestHeaderNavigation(t *testing.T) {
	source := `import HttpRequest from "@std/http.ms"
import Bytes from "@std/bytes.ms"
fn content_type(request: HttpRequest) -> Optional[List[Bytes]]:
    return request.headers.values("content-type")
`
	result := compiler.CompileSource("header.ms", source, compiler.Options{AnalyzeOnly: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	nav, ok := tooling.NavigationAt(result.Program, "header.ms", strings.Index(source, "values("))
	if !ok || nav.Definition.File != "@std/http.ms" || !strings.Contains(nav.Hover, "fn(name: String)->Optional[List[Bytes]]") {
		t.Fatalf("header navigation: %#v, %v", nav, ok)
	}
}

func TestLocalHttpHeadersDoesNotAcquireNativeLookup(t *testing.T) {
	source := `type HttpHeaders:
    value: String
fn lookup(fields: HttpHeaders) -> Unit:
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
