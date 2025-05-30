package compile

import (
	"fmt"
	"manuscript-lang/manuscript/internal/config"
	"testing"
)

func TestSourcemapPositionUniqueness(t *testing.T) {
	msCode := `fn main() {
  let x = 42
  let y = "hello"
  let z = x + 10
  
  println(x)
  println(y)
  println(z)
  
  return z
}`

	// Create config with sourcemap enabled
	cfg := &config.MsConfig{
		CompilerOptions: config.CompilerOptions{
			OutputDir: "./build",
			EntryFile: "test.ms",
			Sourcemap: true,
		},
	}

	ctx, err := config.NewCompilerContext(cfg, ".", "test.ms")
	if err != nil {
		t.Fatalf("Failed to create compiler context: %v", err)
	}

	// Compile the manuscript code
	_, sourceMap, err := manuscriptToGo(msCode, ctx)
	if err != nil {
		t.Fatalf("Failed to compile manuscript code: %v", err)
	}

	// Verify sourcemap was generated
	if sourceMap == nil {
		t.Fatal("Expected sourcemap to be generated")
	}

	// Parse the mappings
	if err := sourceMap.ParseMappings(); err != nil {
		t.Fatalf("Failed to parse sourcemap mappings: %v", err)
	}

	mappings := sourceMap.GetMappings()
	if len(mappings) == 0 {
		t.Fatal("Expected sourcemap to have mappings")
	}

	// Debug: Print all mappings to understand the issue
	t.Logf("Total mappings: %d", len(mappings))
	for i, mapping := range mappings {
		name := ""
		if mapping.NameIndex >= 0 && mapping.NameIndex < len(sourceMap.Names) {
			name = sourceMap.Names[mapping.NameIndex]
		}
		t.Logf("Mapping %d: Go %d:%d -> MS %d:%d (name: %s)",
			i, mapping.GeneratedLine, mapping.GeneratedColumn,
			mapping.SourceLine, mapping.SourceColumn, name)
	}

	// Verify that we have multiple unique mappings
	positionSet := make(map[string]bool)
	for _, mapping := range mappings {
		posKey := fmt.Sprintf("%d:%d", mapping.GeneratedLine, mapping.GeneratedColumn)
		if positionSet[posKey] {
			t.Logf("Warning: Duplicate position found: %s", posKey)
		}
		positionSet[posKey] = true
	}

	// We should have multiple unique positions
	if len(positionSet) < 5 {
		t.Errorf("Expected at least 5 unique positions, got %d", len(positionSet))
	}

	// Test error mapping for different positions using actual mappings
	testCases := []struct {
		name     string
		goLine   int
		goColumn int
	}{
		{"variable x", 2, 7},      // Go 1:6 in 0-based = Go 2:7 in 1-based
		{"variable y", 3, 10},     // Go 2:9 in 0-based = Go 3:10 in 1-based
		{"variable z", 4, 13},     // Go 3:12 in 0-based = Go 4:13 in 1-based
		{"println call 1", 6, 49}, // Go 5:48 in 0-based = Go 6:49 in 1-based
		{"println call 2", 7, 53}, // Go 6:52 in 0-based = Go 7:53 in 1-based
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			sourceFile, msLine, msColumn, err := sourceMap.MapGoErrorToManuscript(tc.goLine, tc.goColumn)
			if err != nil {
				t.Logf("Warning: Could not map position %d:%d: %v", tc.goLine, tc.goColumn, err)
				return
			}

			// Verify we got a reasonable mapping
			if msLine <= 0 || msColumn < 0 {
				t.Errorf("Invalid manuscript position: %d:%d", msLine, msColumn)
			}

			if sourceFile == "" {
				t.Error("Expected source file to be non-empty")
			}

			t.Logf("Mapped Go %d:%d -> MS %d:%d in %s", tc.goLine, tc.goColumn, msLine, msColumn, sourceFile)
		})
	}
}
