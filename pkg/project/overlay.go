package project

import (
	"fmt"
	"sort"
)

// CanonicalOverlay canonicalizes editor snapshots exactly as filesystem reads and imports are
// canonicalized. Two spellings of one file cannot select conflicting content.
func CanonicalOverlay(root string, overlay map[string]string) (map[string]string, error) {
	normalized := make(map[string]string, len(overlay))
	filenames := make([]string, 0, len(overlay))
	for filename := range overlay {
		filenames = append(filenames, filename)
	}
	sort.Strings(filenames)
	for _, filename := range filenames {
		source := overlay[filename]
		canonical, err := SourcePath(root, filename, overlay)
		if err != nil {
			// Documents outside this project never enter its module graph.
			continue
		}
		if previous, ok := normalized[canonical]; ok && previous != source {
			return nil, fmt.Errorf("conflicting editor overlays for %s; two spellings of one path carry different unsaved contents, so send a single snapshot per file", canonical)
		}
		normalized[canonical] = source
	}
	return normalized, nil
}
