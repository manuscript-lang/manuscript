package rt

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

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
		if typ != "TextError" && !strings.Contains(string(messages), "case "+name+":") {
			t.Errorf("errors_messages.go lacks %s", name)
		}
		if shared[tag] && !strings.Contains(string(categories), "func ("+name+") errorCategory()") {
			t.Errorf("errors_category.go lacks %s", name)
		}
		if !shared[tag] && strings.Contains(string(categories), "func ("+name+") errorCategory()") {
			t.Errorf("%s must not have a shared category", name)
		}
	}
}
