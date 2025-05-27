package main

import (
	"flag"
	"fmt"
	"os"

	"manuscript-lang/manuscript/internal/compile"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "build" {
		handleBuildCommand()
		return
	}

	if len(os.Args) != 2 {
		fmt.Println("Usage: msc <file.ms> or msc build [options] [file.ms]")
		return
	}

	compile.RunFile(os.Args[1])
}

func handleBuildCommand() {
	buildCmd := flag.NewFlagSet("build", flag.ExitOnError)
	config := buildCmd.String("config", "", "Path to configuration file (ms.yml)")
	outdir := buildCmd.String("outdir", "", "Output directory")
	debug := buildCmd.Bool("d", false, "Print token stream")
	buildCmd.Parse(os.Args[2:])

	if *config != "" && *outdir != "" {
		fmt.Println("Error: -config cannot be used with -outdir")
		buildCmd.Usage()
		return
	}

	var filename string
	if buildCmd.NArg() >= 1 {
		filename = buildCmd.Arg(0)
	}

	compile.BuildFile(filename, *config, *outdir, *debug)
}
