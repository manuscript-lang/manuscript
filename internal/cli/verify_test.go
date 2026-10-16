package cli

import (
	"encoding/json"
	"testing"
)

func decodeVerify(t *testing.T, output string) verifyResult {
	t.Helper()
	var document verifyResult
	if err := json.Unmarshal([]byte(output), &document); err != nil {
		t.Fatalf("verify --json is not one document: %v\n%s", err, output)
	}
	return document
}

func stepStatuses(document verifyResult) map[string]string {
	statuses := map[string]string{}
	for _, step := range document.Steps {
		statuses[step.Name] = step.Status
	}
	return statuses
}

func TestVerifyReportsEveryStepAsOneDocument(t *testing.T) {
	file := sourceFile(t, "export fn main() -> Int:\n    return 0\n")
	status, output, errors := invoke(t, "verify", file, "--json")
	document := decodeVerify(t, output)
	if status != 0 || !document.OK || errors != "" || len(document.Steps) != 4 {
		t.Fatalf("verify = %d, %+v, %q", status, document, errors)
	}
	for _, step := range document.Steps {
		if step.Status != "passed" || step.Result == nil {
			t.Errorf("step %s = %+v", step.Name, step)
		}
	}
}

func TestVerifyFailingCheckSkipsLintAndTestButStillFormats(t *testing.T) {
	file := sourceFile(t, "export fn main() -> Int:\n    return \"wrong\"\n")
	status, output, _ := invoke(t, "verify", file, "--json")
	document := decodeVerify(t, output)
	want := map[string]string{"check": "failed", "fmt": "passed", "lint": "skipped", "test": "skipped"}
	got := stepStatuses(document)
	for name, state := range want {
		if got[name] != state {
			t.Errorf("%s = %q, want %q", name, got[name], state)
		}
	}
	if status != 1 || document.OK {
		t.Fatalf("status = %d, ok = %v", status, document.OK)
	}
}

func TestVerifyReportsFormattingDriftAndNoTestSkip(t *testing.T) {
	file := sourceFile(t, "export fn main() -> Int:\n    return   0\n")
	status, output, _ := invoke(t, "verify", file, "--json", "--no-test")
	document := decodeVerify(t, output)
	got := stepStatuses(document)
	if status != 1 || got["fmt"] != "failed" || got["test"] != "skipped" || got["check"] != "passed" {
		t.Fatalf("status = %d, steps = %v", status, got)
	}
}

func TestVerifyRejectsBadArguments(t *testing.T) {
	for _, args := range [][]string{{"verify", "a.ms", "b.ms"}, {"verify", "--bogus"}} {
		if status, _, errors := invoke(t, args...); status != 2 || errors == "" {
			t.Errorf("%v = %d, %q", args, status, errors)
		}
	}
}
