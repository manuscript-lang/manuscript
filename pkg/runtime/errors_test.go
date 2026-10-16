package msruntime

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

// hostErrorTypes are the error types whose messages errors_messages.go holds;
// other modules define their own.
var hostErrorTypes = map[string]bool{"IoError": true, "FileSystemError": true, "SystemError": true, "ProcessError": true, "CommandError": true, "LogError": true, "TimeError": true}

var errorCaseDeclaration = regexp.MustCompile(`(?m)^type ([A-Za-z]+Error)_([A-Za-z]+) struct`)

// TestErrorMessageCoverage keeps the generated message and category tables in
// step with the standard error cases in std_types_gen.go: a new case must be
// regenerated into errors_messages.go (and errors_category.go when it has a
// shared category).
func TestErrorMessageCoverage(t *testing.T) {
	types, _ := os.ReadFile("std_types_gen.go")
	messages, _ := os.ReadFile("errors_messages.go")
	categories, _ := os.ReadFile("errors_category.go")
	shared := map[string]bool{"InvalidInput": true, "InvalidData": true, "LimitExceeded": true, "NotFound": true, "AlreadyExists": true, "PermissionDenied": true, "Unsupported": true, "Closed": true, "Timeout": true, "Unavailable": true}
	for _, m := range errorCaseDeclaration.FindAllStringSubmatch(string(types), -1) {
		typ, tag := m[1], m[2]
		name := typ + "_" + tag
		if hostErrorTypes[typ] && !strings.Contains(string(messages), "case "+name+":") {
			t.Errorf("errors_messages.go lacks %s", name)
		}
		if shared[tag] && !strings.Contains(string(categories), "func ("+name+") Category()") {
			t.Errorf("errors_category.go lacks %s", name)
		}
		if !shared[tag] && strings.Contains(string(categories), "func ("+name+") Category()") {
			t.Errorf("%s must not have a shared category", name)
		}
	}
}
