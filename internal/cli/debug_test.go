package cli

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestDebugScriptOptions(t *testing.T) {
	for _, args := range [][]string{{"debug", "missing.ms", "--json"}, {"debug", "missing.ms", "--script", "-"}, {"debug", "missing.ms", "--raw-stack"}, {"run", "missing.ms", "--script=-"}, {"debug", "missing.ms", "--script"}, {"debug", "missing.ms", "--script=-", "--script=-", "--json"}} {
		status, out, err := invoke(t, args...)
		if status != 2 || out != "" || err == "" {
			t.Fatalf("%v: %d %q %q", args, status, out, err)
		}
	}
	for _, args := range [][]string{{"debug", "missing.ms", "--script", "-", "--json"}, {"debug", "missing.ms", "--script=-", "--json", "--raw-stack"}} {
		status, out, err := invoke(t, args...)
		if status != 1 || err != "" {
			t.Fatalf("%v: %d %q %q", args, status, out, err)
		}
		decoder := json.NewDecoder(strings.NewReader(out))
		var events []map[string]any
		for decoder.More() {
			var e map[string]any
			if err := decoder.Decode(&e); err != nil {
				t.Fatal(err)
			}
			events = append(events, e)
		}
		if len(events) != 2 || events[0]["event"] != "error" || events[0]["code"] != "compile" || events[1]["event"] != "exit" {
			t.Fatal(events)
		}
	}
	inv, status, ok := parseInvocation([]string{"debug", "main.ms", "--script=a=b.txt", "--json", "--", "--script=target", "a", "b"})
	if !ok || status != 0 || inv.debugScript != "a=b.txt" || strings.Join(inv.arguments, ",") != "--script=target,a,b" {
		t.Fatal(inv, status, ok)
	}
}
