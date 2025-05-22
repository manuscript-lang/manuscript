package parser

// This is a placeholder package to make the import in main.go work conceptually.
// The actual dummy parser logic used in this step is defined directly in main.go.

type DummyParseError struct {
	Line    int
	Column  int
	Length  int
	Message string
}

type DummyManuscriptParser struct{}

// Parse is a placeholder method.
func (p *DummyManuscriptParser) Parse(uri string, content []byte) []DummyParseError {
	// The actual dummy logic is in main.go for this subtask.
	// This is just to make the import work.
	return nil
}
