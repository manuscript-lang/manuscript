package sourcemap

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// GoError represents a Go compilation error
type GoError struct {
	File    string
	Line    int
	Column  int
	Message string
}

// ManuscriptError represents a mapped Manuscript error
type ManuscriptError struct {
	File    string
	Line    int
	Column  int
	Message string
}

// ParseGoError parses a Go compilation error string
func ParseGoError(errorStr string) (*GoError, error) {
	// Common Go error formats:
	// ./file.go:10:5: error message
	// file.go:10:5: error message
	// file.go:10: error message (no column)

	re := regexp.MustCompile(`^(.+?):(\d+)(?::(\d+))?: (.+)$`)
	matches := re.FindStringSubmatch(strings.TrimSpace(errorStr))

	if len(matches) < 4 {
		return nil, fmt.Errorf("unable to parse Go error: %s", errorStr)
	}

	file := matches[1]
	line, err := strconv.Atoi(matches[2])
	if err != nil {
		return nil, fmt.Errorf("invalid line number in error: %s", matches[2])
	}

	column := 1 // Default column if not specified
	if len(matches) > 3 && matches[3] != "" {
		column, err = strconv.Atoi(matches[3])
		if err != nil {
			return nil, fmt.Errorf("invalid column number in error: %s", matches[3])
		}
	}

	message := matches[4]

	return &GoError{
		File:    file,
		Line:    line,
		Column:  column,
		Message: message,
	}, nil
}

// MapGoErrorToManuscript maps a Go error to a Manuscript error using the source map
func MapGoErrorToManuscript(goError *GoError, sourceMapFile string) (*ManuscriptError, error) {
	// Load the source map
	sourceMap, err := LoadFromFile(sourceMapFile)
	if err != nil {
		return nil, fmt.Errorf("failed to load source map: %v", err)
	}

	// Map the position
	msFile, msLine, msColumn, err := sourceMap.MapGoErrorToManuscript(goError.Line, goError.Column)
	if err != nil {
		return nil, fmt.Errorf("failed to map error position: %v", err)
	}

	return &ManuscriptError{
		File:    msFile,
		Line:    msLine,
		Column:  msColumn,
		Message: goError.Message,
	}, nil
}

// MapGoErrorString maps a Go error string to a Manuscript error string
func MapGoErrorString(goErrorStr string, sourceMapFile string) (string, error) {
	goError, err := ParseGoError(goErrorStr)
	if err != nil {
		return "", err
	}

	msError, err := MapGoErrorToManuscript(goError, sourceMapFile)
	if err != nil {
		return "", err
	}

	return fmt.Sprintf("%s:%d:%d: %s", msError.File, msError.Line, msError.Column, msError.Message), nil
}

// FormatManuscriptError formats a Manuscript error for display
func (me *ManuscriptError) String() string {
	return fmt.Sprintf("%s:%d:%d: %s", me.File, me.Line, me.Column, me.Message)
}
