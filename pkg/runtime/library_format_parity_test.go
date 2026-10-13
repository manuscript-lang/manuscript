package msruntime

import (
	"context"
	"strings"
	"testing"
	"time"
)

func htmlParityNode(tag string, fields ...Value) Alternative {
	return Alternative{Type: "@std/HtmlNode", Tag: tag, Fields: fields}
}

func TestHTMLStringifyRoundTripAndSharedNodes(t *testing.T) {
	text := `<!DOCTYPE html PUBLIC "pub" "sys"><!--note--><svg><a xlink:href="#icon">é🙂 &amp; text</a></svg><script>if (a < b) x = '&amp;';</script><pre>` + "\nline" + `</pre>`
	value := librarySuccess(t, libraryCall(t, "html/parse", text))
	encoded := librarySuccess(t, libraryCall(t, "html/stringify", value)).(string)
	decoded := librarySuccess(t, libraryCall(t, "html/parse", encoded))
	if !Equal(value, decoded) {
		t.Fatalf("HTML tree changed after stringify/parse: %s", encoded)
	}
	shared := libraryList("@std/HtmlNode", []Value{htmlParityNode("Text", "é & <")})
	child := htmlParityNode("Element", "b", "", libraryList("@std/HtmlAttribute", nil), shared)
	root := htmlParityNode("Document", libraryList("@std/HtmlNode", []Value{child, child}))
	if got := librarySuccess(t, libraryCall(t, "html/stringify", root)).(string); got != "<b>é &amp; &lt;</b><b>é &amp; &lt;</b>" {
		t.Fatal(got)
	}
}

func TestHTMLStringifyRejectsCyclesMalformedNodesAndLimits(t *testing.T) {
	children := libraryList("@std/HtmlNode", nil)
	cycle := htmlParityNode("Element", "div", "", libraryList("@std/HtmlAttribute", nil), children)
	children.Items = []Value{cycle}
	attribute := func(name string) Record {
		return Record{Type: "@std/HtmlAttribute", Fields: map[string]Value{"name": name, "namespace": "", "value": "text"}}
	}
	for _, invalid := range []Value{
		cycle,
		htmlParityNode("Text", "\xff"),
		htmlParityNode("Text", "\x00"),
		htmlParityNode("Text"),
		htmlParityNode("Unknown"),
		htmlParityNode("Doctype", "html", "both'\"quotes", ""),
		htmlParityNode("Element", "x onclick=bad", "", libraryList("@std/HtmlAttribute", nil), libraryList("@std/HtmlNode", nil)),
		htmlParityNode("Element", "br", "", libraryList("@std/HtmlAttribute", nil), libraryList("@std/HtmlNode", []Value{htmlParityNode("Text", "child")})),
		htmlParityNode("Element", "div", "", libraryList("@std/HtmlAttribute", []Value{attribute("bad name")}), libraryList("@std/HtmlNode", nil)),
		htmlParityNode("Element", "div", "", libraryList("@std/HtmlAttribute", nil), libraryList("@std/HtmlNode", []Value{htmlParityNode("Document", libraryList("@std/HtmlNode", nil))})),
	} {
		libraryFailure(t, libraryCall(t, "html/stringify", invalid), "InvalidData")
	}
	root := htmlParityNode("Document", libraryList("@std/HtmlNode", []Value{htmlParityNode("Text", "é &")}))
	for _, limits := range []map[string]Value{
		{"max_bytes": int64(7)},
		{"max_depth": int64(0)},
		{"max_nodes": int64(1)},
	} {
		libraryFailure(t, libraryCall(t, "html/stringify", root, Record{Type: "@std/HtmlLimits", Fields: limits}), "LimitExceeded")
	}
	limits := Record{Type: "@std/HtmlLimits", Fields: map[string]Value{"max_bytes": int64(8), "max_depth": int64(1), "max_nodes": int64(2)}}
	if got := librarySuccess(t, libraryCall(t, "html/stringify", root, limits)); got != "é &amp;" {
		t.Fatal(got)
	}
	for _, field := range []string{"max_bytes", "max_depth", "max_nodes"} {
		libraryFailure(t, libraryCall(t, "html/stringify", root, Record{Type: "@std/HtmlLimits", Fields: map[string]Value{field: int64(-1)}}), "InvalidInput")
	}
}

func TestHTMLStringifyDeepAndCancellation(t *testing.T) {
	var root Value = htmlParityNode("Text", "deep")
	for range 1000 {
		root = htmlParityNode("Element", "div", "", libraryList("@std/HtmlAttribute", nil), libraryList("@std/HtmlNode", []Value{root}))
	}
	librarySuccess(t, libraryCall(t, "html/stringify", root))
	ctx := RootExecution()
	cancelledContext, cancel := context.WithCancel(ctx.Context)
	cancel()
	ctx.Context = cancelledContext
	function := StandardFunction("html/stringify", libraryRuntimeType(libraryResult("String", "HtmlError"))).(Function)
	if _, ok := recovered(func() { function.Body(ctx, []Value{root}) }).(cancelled); !ok {
		t.Fatal("HTML stringify lost cancellation")
	}
	workContext, stop := context.WithCancel(context.Background())
	defer stop()
	work := &stringWorkCancellation{Context: workContext, cancel: stop}
	ctx = RootExecution()
	ctx.Context = work
	if _, ok := recovered(func() { function.Body(ctx, []Value{htmlParityNode("Text", strings.Repeat("é &", 10000))}) }).(cancelled); !ok || work.checks < 2 {
		t.Fatalf("HTML render lost work cancellation: %d checks", work.checks)
	}
}

func TestTimestampLayoutsUTCPrecisionAndErrors(t *testing.T) {
	stamp := libraryTimestamp{time.Date(2024, 2, 29, 10, 20, 30, 123456789, time.UTC)}
	layout := "2006-01-02 15:04:05.000000000 -07:00"
	function := StandardFunction("time/timestamp_format", "String").(Function)
	encoded := function.Body(RootExecution(), []Value{stamp, layout}).(string)
	if encoded != "2024-02-29 10:20:30.123456789 +00:00" {
		t.Fatal(encoded)
	}
	if got := librarySuccess(t, libraryCall(t, "time/parse_timestamp_format", encoded, layout)); !Equal(got, stamp) {
		t.Fatal(got)
	}
	for _, text := range []string{"2024-02-29 12:20:30.123456789 +02:00", encoded} {
		if got := librarySuccess(t, libraryCall(t, "time/parse_timestamp_format", text, layout)); !Equal(got, stamp) {
			t.Fatal(got)
		}
	}
	date := librarySuccess(t, libraryCall(t, "time/parse_timestamp_format", "2024-02-29", "2006-01-02")).(libraryTimestamp)
	if date.t.Hour() != 0 || date.t.Location() != time.UTC {
		t.Fatal(date)
	}
	libraryFailure(t, libraryCall(t, "time/parse_timestamp_format", "", ""), "InvalidInput")
	libraryFailure(t, libraryCall(t, "time/parse_timestamp_format", "2024-02-30", "2006-01-02"), "InvalidData")
	libraryFailure(t, libraryCall(t, "time/parse_timestamp_format", "00:00:00", "15:04:05"), "OutOfRange")
	libraryFailure(t, libraryCall(t, "time/parse_timestamp_format", "0001-01-01T00:00:00+01:00", time.RFC3339), "OutOfRange")
}

func TestTimestampLayoutCancellation(t *testing.T) {
	for _, test := range []struct {
		name, result string
		args         []Value
	}{
		{"time/timestamp_format", "String", []Value{libraryTimestamp{time.Unix(0, 0).UTC()}, "2006-01-02"}},
		{"time/parse_timestamp_format", libraryRuntimeType(libraryResult("Timestamp", "TimeError")), []Value{"2024-02-29", "2006-01-02"}},
	} {
		function := StandardFunction(test.name, test.result).(Function)
		ctx := RootExecution()
		cancelledContext, cancel := context.WithCancel(ctx.Context)
		cancel()
		ctx.Context = cancelledContext
		if _, ok := recovered(func() { function.Body(ctx, test.args) }).(cancelled); !ok {
			t.Fatalf("%s lost entry cancellation", test.name)
		}
		workContext, stop := context.WithCancel(context.Background())
		work := &stringWorkCancellation{Context: workContext, cancel: stop}
		ctx = RootExecution()
		ctx.Context = work
		failure := recovered(func() { function.Body(ctx, test.args) })
		stop()
		if _, ok := failure.(cancelled); !ok || work.checks < 2 {
			t.Fatalf("%s lost post-codec cancellation: %#v (%d checks)", test.name, failure, work.checks)
		}
	}
}
