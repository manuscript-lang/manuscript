package tooling

import "testing"

func TestLintCoordinates(t *testing.T) {
	findings := Lint("file.ms", "# é  \r\n# end")
	if len(findings) != 2 || findings[0].Code != "MSL001" || findings[0].Position.Offset != 4 || findings[1].Position.Line != 2 {
		t.Fatal(findings)
	}
	if len(Lint("file.ms", "# clean\n")) != 0 {
		t.Fatal("clean source flagged")
	}
}
