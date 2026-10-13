package cli

import (
	"fmt"
	"os"

	support "github.com/manuscript-lang/manuscript"
)

func runVersion(command string, arguments []string) int {
	if command == "version" && len(arguments) == 1 && (arguments[0] == "--help" || arguments[0] == "-h") {
		usage, _ := commandHelp(command)
		fmt.Print(usage)
		return 0
	}
	if len(arguments) != 0 {
		fmt.Fprintf(os.Stderr, "ms %s takes no arguments; use ms version or ms --version\n", command)
		return 2
	}
	fmt.Println("Manuscript " + support.Version())
	return 0
}
