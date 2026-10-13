package cli

import (
	"fmt"
	"os"

	support "github.com/manuscript-lang/manuscript"
)

func runVersion(command string, arguments []string) int {
	if len(arguments) != 0 {
		fmt.Fprintf(os.Stderr, "ms %s takes no arguments; use ms version or ms --version\n", command)
		return 2
	}
	fmt.Println("Manuscript " + support.Version())
	return 0
}
