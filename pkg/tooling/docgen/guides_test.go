package docgen

import (
	"testing"
	"testing/fstest"
)

func TestGuideFiles(t *testing.T) {
	source := "# Sample\n\n```manuscript\nexport fn main() -> Unit:\n    print(\"hello\")\n```\n"
	files, err := guideFiles(fstest.MapFS{"guides/documentation/standard-library/sample.md": &fstest.MapFile{Data: []byte(source)}})
	if err != nil {
		t.Fatal(err)
	}
	if string(files["documentation/standard-library/sample.md"]) != source {
		t.Fatalf("guide changed Markdown or code indentation: %q", files)
	}
}
