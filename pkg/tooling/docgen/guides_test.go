package docgen

import (
	"strings"
	"testing"
	"testing/fstest"
)

func TestGuideBlocks(t *testing.T) {
	source := "# Detached declaration prose\nexport fn sample() -> Unit:\n\n# documentation documentation/standard-library/sample.md\n# # Sample\n#\n# ```manuscript\n# export fn main() -> Unit:\n#     print(\"hello\")\n# ```\n# end-documentation\n"
	files, err := guideFiles(fstest.MapFS{"sample.ms": &fstest.MapFile{Data: []byte(source)}})
	if err != nil {
		t.Fatal(err)
	}
	want := "# Sample\n\n```manuscript\nexport fn main() -> Unit:\n    print(\"hello\")\n```\n"
	if string(files["documentation/standard-library/sample.md"]) != want {
		t.Fatalf("guide changed Markdown or code indentation: %q", files)
	}
	for _, test := range []struct{ name, source, error string }{
		{"escape", "# documentation documentation/standard-library/../../../escaped.md\n", "invalid documentation path"},
		{"nested", "# documentation documentation/standard-library/a.md\n# documentation documentation/standard-library/b.md\n", "nested documentation block"},
		{"unterminated", "# documentation documentation/standard-library/a.md\n", "unterminated"},
		{"code", "# documentation documentation/standard-library/a.md\nexport fn sample() -> Unit:\n", "top-level comments"},
		{"terminator", "# end-documentation\n", "unexpected"},
		{"duplicate", "# documentation documentation/standard-library/a.md\n# end-documentation\n# documentation documentation/standard-library/a.md\n# end-documentation\n", "duplicate"},
	} {
		t.Run(test.name, func(t *testing.T) {
			_, err := guideFiles(fstest.MapFS{"bad.ms": &fstest.MapFile{Data: []byte(test.source)}})
			if err == nil || !strings.Contains(err.Error(), test.error) {
				t.Fatalf("got %v; want %s", err, test.error)
			}
		})
	}
}
