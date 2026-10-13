package syntax_test

import (
	"encoding/json"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestDiagnosticJSONIsAdditive(t *testing.T) {
	d := syntax.Diagnostic{Position: syntax.Position{File: "test.ms", Line: 1, Column: 1}, Phase: "parse", Message: "expected a name; write one"}
	data, err := json.Marshal(d)
	if err != nil {
		t.Fatal(err)
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		t.Fatal(err)
	}
	if len(fields) != 4 || fields["code"] == nil || fields["phase"] == nil || fields["message"] == nil || fields["position"] == nil {
		t.Fatalf("legacy schema changed: %s", data)
	}
	end := syntax.Position{File: "test.ms", Line: 1, Column: 3, Offset: 2}
	d.End = &end
	d.Fix = &syntax.DiagnosticFix{Position: d.Position, End: end, Replacement: "name"}
	data, err = json.Marshal(d)
	if err != nil {
		t.Fatal(err)
	}
	var roundtrip syntax.Diagnostic
	if err := json.Unmarshal(data, &roundtrip); err != nil {
		t.Fatal(err)
	}
	if roundtrip.End == nil || *roundtrip.End != end || roundtrip.Fix == nil || *roundtrip.Fix != *d.Fix || roundtrip.Error() != d.Error() {
		t.Fatalf("lost range/fix: %s", data)
	}
}
