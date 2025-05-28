package sourcemap

import (
	"encoding/json"
	"fmt"
	"go/ast"
	"go/token"
	"os"
	"path/filepath"
	"sort"
	"strings"

	mast "manuscript-lang/manuscript/internal/ast"
)

// SourceMap represents a source map for mapping between Manuscript and Go code
type SourceMap struct {
	Version    int      `json:"version"`
	Sources    []string `json:"sources"`
	Names      []string `json:"names"`
	Mappings   string   `json:"mappings"`
	SourceRoot string   `json:"sourceRoot,omitempty"`
	File       string   `json:"file,omitempty"`

	// Internal state for building mappings
	mappings []Mapping
}

// Mapping represents a single position mapping
type Mapping struct {
	GeneratedLine   int // 0-based line in generated Go code
	GeneratedColumn int // 0-based column in generated Go code
	SourceIndex     int // Index into Sources array
	SourceLine      int // 0-based line in original Manuscript code
	SourceColumn    int // 0-based column in original Manuscript code
	NameIndex       int // Index into Names array (-1 if no name)
}

// Builder helps build source maps during transpilation and after printing
type Builder struct {
	sourceMap    *SourceMap
	sourceFiles  map[string]int // Map source file paths to indices
	names        map[string]int // Map names to indices
	fileSet      *token.FileSet
	goFile       *token.File
	msSourceFile string
	nodeMap      map[ast.Node]*mast.BaseNode // Maps Go AST nodes to Manuscript AST nodes for post-print mapping
}

// NewBuilder creates a new source map builder
func NewBuilder(msSourceFile string, goFileName string) *Builder {
	builder := &Builder{
		sourceMap: &SourceMap{
			Version:  3,
			Sources:  []string{},
			Names:    []string{},
			Mappings: "",
			File:     goFileName,
		},
		sourceFiles:  make(map[string]int),
		names:        make(map[string]int),
		fileSet:      token.NewFileSet(),
		msSourceFile: msSourceFile,
		nodeMap:      make(map[ast.Node]*mast.BaseNode),
	}

	// Pre-add the source file
	builder.getOrAddSource(msSourceFile)
	return builder
}

// RegisterNodeMapping registers a mapping between a Go AST node and Manuscript AST node (post-print approach)
func (b *Builder) RegisterNodeMapping(goNode ast.Node, msNode mast.Node) {
	if goNode != nil && msNode != nil {
		// Extract position from the manuscript node
		pos := msNode.Pos()
		baseNode := &mast.BaseNode{Position: pos}
		b.nodeMap[goNode] = baseNode
	}
}

// SetGoFile sets the Go file for position calculations
func (b *Builder) SetGoFile(file *token.File) {
	b.goFile = file
}

// getOrAddSource gets or adds a source file to the sources array
func (b *Builder) getOrAddSource(sourcePath string) int {
	if index, exists := b.sourceFiles[sourcePath]; exists {
		return index
	}

	index := len(b.sourceMap.Sources)
	b.sourceMap.Sources = append(b.sourceMap.Sources, sourcePath)
	b.sourceFiles[sourcePath] = index
	return index
}

// Build finalizes the source map and generates the mappings string
func (b *Builder) Build() *SourceMap {
	// Sort mappings by generated position
	sort.Slice(b.sourceMap.mappings, func(i, j int) bool {
		a, b := b.sourceMap.mappings[i], b.sourceMap.mappings[j]
		if a.GeneratedLine != b.GeneratedLine {
			return a.GeneratedLine < b.GeneratedLine
		}
		return a.GeneratedColumn < b.GeneratedColumn
	})

	// Generate VLQ-encoded mappings string
	b.sourceMap.Mappings = b.encodeMappings()

	return b.sourceMap
}

// encodeMappings encodes the mappings array into a VLQ string
func (b *Builder) encodeMappings() string {
	if len(b.sourceMap.mappings) == 0 {
		return ""
	}

	var result strings.Builder
	var prevGeneratedColumn int
	var prevSourceIndex, prevSourceLine, prevSourceColumn, prevNameIndex int

	currentLine := -1

	for _, mapping := range b.sourceMap.mappings {
		// Add semicolons for new lines
		for currentLine < mapping.GeneratedLine {
			if currentLine >= 0 {
				result.WriteString(";")
			}
			currentLine++
			prevGeneratedColumn = 0 // Reset column for new line
		}

		// Add comma separator if not the first mapping on this line
		if mapping.GeneratedLine == currentLine && result.Len() > 0 &&
			!strings.HasSuffix(result.String(), ";") {
			result.WriteString(",")
		}

		// Encode the mapping
		values := []int{
			mapping.GeneratedColumn - prevGeneratedColumn,
			mapping.SourceIndex - prevSourceIndex,
			mapping.SourceLine - prevSourceLine,
			mapping.SourceColumn - prevSourceColumn,
		}

		if mapping.NameIndex >= 0 {
			values = append(values, mapping.NameIndex-prevNameIndex)
		}

		for _, value := range values {
			result.WriteString(VLQEncode(value))
		}

		// Update previous values
		prevGeneratedColumn = mapping.GeneratedColumn
		prevSourceIndex = mapping.SourceIndex
		prevSourceLine = mapping.SourceLine
		prevSourceColumn = mapping.SourceColumn
		if mapping.NameIndex >= 0 {
			prevNameIndex = mapping.NameIndex
		}
	}

	return result.String()
}

// WriteToFile writes the source map to a file
func (sm *SourceMap) WriteToFile(filename string) error {
	data, err := json.MarshalIndent(sm, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal source map: %v", err)
	}

	if err := os.WriteFile(filename, data, 0644); err != nil {
		return fmt.Errorf("failed to write source map file: %v", err)
	}

	return nil
}

// LoadFromFile loads a source map from a file
func LoadFromFile(filename string) (*SourceMap, error) {
	data, err := os.ReadFile(filename)
	if err != nil {
		return nil, fmt.Errorf("failed to read source map file: %v", err)
	}

	var sm SourceMap
	if err := json.Unmarshal(data, &sm); err != nil {
		return nil, fmt.Errorf("failed to unmarshal source map: %v", err)
	}

	return &sm, nil
}

// MapGoErrorToManuscript maps a Go compilation error back to Manuscript source
func (sm *SourceMap) MapGoErrorToManuscript(goLine, goColumn int) (string, int, int, error) {
	// Parse the mappings if not already done
	if len(sm.mappings) == 0 {
		if err := sm.parseMappings(); err != nil {
			return "", 0, 0, fmt.Errorf("failed to parse mappings: %v", err)
		}
	}

	// Find the best mapping for this position
	// We want to find the mapping that is closest to the error position
	var bestMapping *Mapping
	minDistance := int(^uint(0) >> 1) // Max int

	for _, mapping := range sm.mappings {
		// Skip mappings on different lines
		if mapping.GeneratedLine != goLine-1 {
			continue
		}

		// Calculate distance from error position
		distance := mapping.GeneratedColumn - (goColumn - 1)
		if distance < 0 {
			distance = -distance
		}

		// If this mapping is closer to the error position, use it
		if distance < minDistance {
			minDistance = distance
			bestMapping = &mapping
		}
	}

	// If no mapping found on the same line, fall back to closest preceding mapping
	if bestMapping == nil {
		bestMapping = &Mapping{GeneratedLine: -1}
		for _, mapping := range sm.mappings {
			if mapping.GeneratedLine > goLine-1 {
				break
			}
			if mapping.GeneratedLine == goLine-1 && mapping.GeneratedColumn > goColumn-1 {
				break
			}
			*bestMapping = mapping
		}

		if bestMapping.GeneratedLine == -1 {
			return "", 0, 0, fmt.Errorf("no mapping found for position %d:%d", goLine, goColumn)
		}
	}

	if bestMapping.SourceIndex >= len(sm.Sources) {
		return "", 0, 0, fmt.Errorf("invalid source index: %d", bestMapping.SourceIndex)
	}

	return sm.Sources[bestMapping.SourceIndex],
		bestMapping.SourceLine + 1, // Convert back to 1-based
		bestMapping.SourceColumn + 1, // Convert back to 1-based
		nil
}

// parseMappings parses the VLQ-encoded mappings string
func (sm *SourceMap) parseMappings() error {
	if sm.Mappings == "" {
		return nil
	}

	var mappings []Mapping
	var generatedLine int
	var prevGeneratedColumn, prevSourceIndex, prevSourceLine, prevSourceColumn, prevNameIndex int

	lines := strings.Split(sm.Mappings, ";")
	for lineIndex, line := range lines {
		generatedLine = lineIndex
		prevGeneratedColumn = 0 // Reset for each line

		if line == "" {
			continue
		}

		segments := strings.Split(line, ",")
		for _, segment := range segments {
			if segment == "" {
				continue
			}

			values, err := VLQDecodeMultiple(segment)
			if err != nil {
				return fmt.Errorf("failed to decode VLQ segment '%s': %v", segment, err)
			}

			if len(values) < 4 {
				continue // Skip incomplete mappings
			}

			mapping := Mapping{
				GeneratedLine:   generatedLine,
				GeneratedColumn: prevGeneratedColumn + values[0],
				SourceIndex:     prevSourceIndex + values[1],
				SourceLine:      prevSourceLine + values[2],
				SourceColumn:    prevSourceColumn + values[3],
				NameIndex:       -1,
			}

			if len(values) >= 5 {
				mapping.NameIndex = prevNameIndex + values[4]
				prevNameIndex = mapping.NameIndex
			}

			mappings = append(mappings, mapping)

			// Update previous values
			prevGeneratedColumn = mapping.GeneratedColumn
			prevSourceIndex = mapping.SourceIndex
			prevSourceLine = mapping.SourceLine
			prevSourceColumn = mapping.SourceColumn
		}
	}

	sm.mappings = mappings
	return nil
}

// GetSourceMapComment returns the source map comment to add to generated Go files
func GetSourceMapComment(sourceMapFile string) string {
	return fmt.Sprintf("//# sourceMappingURL=%s", filepath.Base(sourceMapFile))
}

// GetFileSet returns the file set used by the builder
func (b *Builder) GetFileSet() *token.FileSet {
	return b.fileSet
}

// ParseMappings parses the VLQ-encoded mappings string (public method)
func (sm *SourceMap) ParseMappings() error {
	return sm.parseMappings()
}

// GetMappings returns the parsed mappings
func (sm *SourceMap) GetMappings() []Mapping {
	return sm.mappings
}
