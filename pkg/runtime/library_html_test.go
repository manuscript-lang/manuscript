package msruntime

import (
	"context"
	"strings"
	"testing"
)

func TestHTMLParseLimitsAndInvalidUTF8(t *testing.T) {
	// An empty document has Document, html, head, and body nodes. The
	// synthesized head/body nodes have depth two.
	for _, test := range []struct {
		text   string
		limits map[string]Value
		code   string
	}{
		{"", map[string]Value{"max_bytes": int64(0), "max_depth": int64(2), "max_nodes": int64(4)}, ""},
		{"", map[string]Value{"max_nodes": int64(3)}, "LimitExceeded"},
		{"", map[string]Value{"max_nodes": int64(0)}, "LimitExceeded"},
		{"", map[string]Value{"max_depth": int64(1)}, "LimitExceeded"},
		{"", map[string]Value{"max_depth": int64(0)}, "LimitExceeded"},
		{"é", map[string]Value{"max_bytes": int64(1)}, "LimitExceeded"},
		{"é", map[string]Value{"max_bytes": int64(2)}, ""},
		{"\xff", nil, "InvalidData"},
	} {
		result := libraryCall(t, "html/parse", test.text, Record{Type: "@std/HtmlLimits", Fields: test.limits})
		if test.code == "" {
			librarySuccess(t, result)
		} else {
			libraryFailure(t, result, test.code)
		}
	}
	for _, field := range []string{"max_bytes", "max_depth", "max_nodes"} {
		limits := Record{Type: "@std/HtmlLimits", Fields: map[string]Value{field: optional("Int", int64(-1), true)}}
		libraryFailure(t, libraryCall(t, "html/parse", "", optional("@std/HtmlLimits", limits, true)), "InvalidInput")
	}
}

func TestHTMLParseLargeAndDeepDocuments(t *testing.T) {
	for _, text := range []string{
		strings.Repeat("<p>é &amp; 🙂</p>", 1000),
		strings.Repeat("<div>", 600) + "deep" + strings.Repeat("</div>", 600),
	} {
		librarySuccess(t, libraryCall(t, "html/parse", text))
	}
}

func TestHTMLParseCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	function := StandardFunction("html/parse", libraryRuntimeType(libraryResult("HtmlNode", "HtmlError"))).(Function)
	if _, ok := recovered(func() {
		function.Body(&Execution{Context: ctx}, []Value{strings.Repeat("x", 10000)})
	}).(cancelled); !ok {
		t.Fatal("HTML parse lost cancellation")
	}
}

func TestHTMLUnescapeCancellationAndMetadata(t *testing.T) {
	function := StandardFunction("html/unescape", "String").(Function)
	if strings.Join(function.Labels, ",") != "text" || function.Result != "String" {
		t.Fatal("wrong HTML unescape metadata", function.Labels, function.Result)
	}
	ctx := RootExecution()
	cancelledContext, cancel := context.WithCancel(ctx.Context)
	cancel()
	ctx.Context = cancelledContext
	if failure := recovered(func() { Invoke(ctx, function, []Argument{{"text", ""}}) }); failure != (cancelled{}) {
		t.Fatalf("HTML unescape lost entry cancellation: %#v", failure)
	}
	ctx = RootExecution()
	workContext, cancel := context.WithCancel(context.Background())
	defer cancel()
	work := &stringWorkCancellation{Context: workContext, cancel: cancel}
	ctx.Context = work
	failure := recovered(func() { function.Body(ctx, []Value{strings.Repeat("&amp;é", 1024)}) })
	if _, ok := failure.(cancelled); !ok || work.checks < 2 {
		t.Fatalf("HTML unescape lost post-codec cancellation: %#v (%d checks)", failure, work.checks)
	}
}
