package lsp

import (
	"strings"
	"testing"
)

func TestTaskGroupSourceSignatureAndNavigation(t *testing.T) {
	source := `import TaskGroup from "@std/tasks.ms"
fn number() -> Int: return 7
fn run() -> Unit:
    with group = TaskGroup():
        let task = group.start(number)
        task.join()
`
	d := document{"file:///tmp/tasks.ms", source, 1}
	result := analyze(d, map[string]document{d.URI: d})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	cursor := strings.Index(source, "start(number)")
	definition := navigation(result, d, Position(source, cursor), "textDocument/definition")
	if definition == nil {
		t.Fatal("missing source definition for start")
	}
	location := definition.([]any)[0].(map[string]any)
	if !strings.Contains(location["uri"].(string), "tasks.ms") {
		t.Fatal(location)
	}
	signature := signatureSource(t, strings.Replace(source, "task.join()", "task.join(|)", 1))
	label := signature["signatures"].([]any)[0].(map[string]any)["label"].(string)
	if label != "task.join() -> Result[Int, ExecutionError]" {
		t.Fatal(label)
	}
	items := completeSource(t, strings.Replace(source, "task.join()", "task.|", 1))
	join := itemNamed(items, "join")
	if join == nil || !strings.Contains(join.Detail, "Result[Int, ExecutionError]") {
		t.Fatal(items)
	}
}
