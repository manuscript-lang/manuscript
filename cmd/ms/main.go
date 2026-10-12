// ms is the Manuscript command-line entry point.
package main

import (
	"github.com/manuscript-lang/manuscript/internal/cli"
	"os"
)

func main() { os.Exit(cli.Run(os.Args[1:])) }
