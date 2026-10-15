package main

import (
	"fmt"
	"os"

	"github.com/manuscript-lang/manuscript/pkg/golower"
)

func init() {
	if len(os.Args) > 1 && os.Args[1] == "stdgen" {
		text, err := golower.StandardRuntime()
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		fmt.Print(text)
		os.Exit(0)
	}
}
