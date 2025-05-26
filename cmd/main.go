package main

import (
	"flag"
	"fmt"
	"os"

	"manuscript-lang/manuscript/internal/compile"
)

func main() {
	// Check for build subcommand
	if len(os.Args) > 1 && os.Args[1] == "build" {
		handleBuildCommand()
		return
	}

	// Default run command
	if len(os.Args) != 2 {
		fmt.Println("Usage: msc <file.ms> or msc build [options] <file.ms>")
		return
	}

	filename := os.Args[1]
	compile.RunFile(filename)
}

func handleBuildCommand() {
	buildCmd := flag.NewFlagSet("build", flag.ExitOnError)
	config := buildCmd.String("config", "", "Path to configuration file (ms.yml)")
	outdir := buildCmd.String("outdir", "", "Output directory")
	debug := buildCmd.Bool("d", false, "Print token stream")
	buildCmd.Parse(os.Args[2:])

	if buildCmd.NArg() < 1 {
		buildCmd.Usage()
		return
	}

	if *config != "" && *outdir != "" {
		fmt.Println("Error: -config cannot be used with -outdir")
		buildCmd.Usage()
		return
	}

	filename := buildCmd.Arg(0)
	compile.BuildFile(filename, *config, *outdir, *debug)
}
