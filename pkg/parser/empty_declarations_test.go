package parser

import (
	"strings"
	"testing"
)

func TestEmptyFunctionDeclarations(t *testing.T) {
	for _, source := range []string{
		"export fn commands() Commands:\n",
		"export type Duration:\n",
		"type List[T]:\nimpl List[T]:\n    fn map[U](transform: fn(value: T) U) List[U]:\n    fn length() Int:\n",
		"type Optional[T]:\n    case none\n    case some(value: T)\nimpl Optional[T]:\n    fn get() T:\n",
		"type Counter:\n    value: Int\nimpl Counter:\n    fn double() Int:\n        return self.value * 2\n",
		"interface Read:\n    fn read(limit: Optional[Int] = none) Int\n",
		"impl Error for Failure:\n    fn message() String:\n",
		"type Options:\n    count: Int = 3\n    total: Int = count + 1\n",
		"fn empty() Unit:\n# empty body\nfn answer() Int: return 3\n",
	} {
		for _, text := range []string{source, strings.ReplaceAll(source, "\n", "\r\n")} {
			if _, err := Parse("ordinary.ms", text); err != nil {
				t.Errorf("%s: %v", text, err)
			}
			if _, issues := ParsePartial("ordinary.ms", text); len(issues) != 0 {
				t.Errorf("partial %s: %v", text, issues)
			}
		}
	}
	for _, source := range []string{
		"export fn commands() Commands\n",
		"type List[T]:\nimpl List[T]:\n    fn get() T\n",
		"type List[T]:\n    fn get() T:\n",
		"type A:\n    x: Int\n    fn f() Int:\n        return x\n",
		"impl Show Point:\n    fn show() String:\n",
		"type Duration\n",
		"native fn commands() Commands\n",
		"fn f() Unit:\n    if true:\n",
		"fn f() Unit:\n    while true:\n",
		"test \"empty\":\n",
		"fn f(callback: fn(value: Int = 3) Int) Unit: return unit\n",
	} {
		if _, err := Parse("ordinary.ms", source); err == nil {
			t.Errorf("accepted %s", source)
		}
	}
}

func TestEmptyDeclarationsPreserveFollowingPositions(t *testing.T) {
	source := "type Empty:\nfn empty() Unit:\nfn kept() Int:\n    return 3\n"
	module, err := Parse("empty.ms", source)
	if err != nil || len(module.Declarations) != 3 || module.Declarations[2].Pos.Line != 3 || module.Declarations[2].Pos.Offset != strings.Index(source, "fn kept") {
		t.Fatal(module, err)
	}
}
