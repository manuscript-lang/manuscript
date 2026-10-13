package msruntime

import "encoding/hex"

func init() {
	libraryAdd("errors", "category", "Optional[ErrorCategory]", []LibraryParam{{"cause", "Error"}}, func(ctx *Execution, _ string, args []Value) Value {
		CheckCancelled(ctx)
		return libraryErrorCategory(args[0])
	})
}

// Classification reads the concrete standard error without a message call or
// translation. Views retain their original receiver and implementation scope.
func libraryErrorCategory(value Value) Value {
	for {
		view, ok := value.(View)
		if !ok {
			break
		}
		value = view.Receiver
	}
	cause, ok := value.(Alternative)
	if !ok || standardErrorDomains[cause.Type] == "" && !sourceStandardErrors[cause.Type] {
		return optional("@std/ErrorCategory", nil, false)
	}
	name := cause.Tag
	if name == "TimedOut" {
		name = "Timeout"
	}
	switch name {
	case "InvalidInput", "InvalidData", "LimitExceeded", "NotFound", "AlreadyExists", "PermissionDenied", "Unsupported", "Closed", "Timeout", "Unavailable":
		return optional("@std/ErrorCategory", Alternative{Type: "@std/ErrorCategory", Tag: name}, true)
	}
	return optional("@std/ErrorCategory", nil, false)
}

// Source-defined standard errors have ordinary nominal module identities,
// rather than the native @std/Type identities. Do not match display names.
var sourceStandardErrors = map[string]bool{
	librarySourceErrorType("@std/yaml.ms", "YamlError"): true,
	librarySourceErrorType("@std/toml.ms", "TomlError"): true,
}

func librarySourceErrorType(module, name string) string {
	// This is the existing source identity format in pkg/checker/checker.go.
	// Called native tests cover both standard source errors and local lookalikes.
	return "module/" + hex.EncodeToString([]byte(module)) + "#" + name
}
