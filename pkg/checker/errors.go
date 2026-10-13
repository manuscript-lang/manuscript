package checker

// Error is the common boundary for explicitly implemented domain errors.
// Other contracts and generic applications retain their exact compatibility.
func (c *checker) errorAssignable(actual, expected *Type) bool {
	if actual == nil || expected == nil {
		return false
	}
	if std(expected, "Error") {
		return c.implements(actual, expected)
	}
	return std(actual, "Result") && std(expected, "Result") &&
		len(actual.Args) == 2 && len(expected.Args) == 2 &&
		Same(actual.Args[0], expected.Args[0]) && std(expected.Args[1], "Error") &&
		c.implements(actual.Args[1], expected.Args[1])
}

// Ordinary domain errors pass through unchanged. Local implementations and
// generic receivers retain the dispatch evidence needed outside this module.
func (c *checker) errorNeedsScope(receiver *Type) bool {
	if receiver.Kind == "variable" || len(receiver.Args) > 0 {
		return true
	}
	for _, method := range c.methods(receiver, "message") {
		if std(method.Contract, "Error") && method.Local {
			return true
		}
	}
	return false
}
