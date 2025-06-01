package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"manuscript-lang/manuscript/internal/compile"
	"manuscript-lang/manuscript/internal/config"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: msc <file.ms> or msc build [options] [file.ms]")
		return
	}

	if os.Args[1] == "build" {
		buildCmd := flag.NewFlagSet("build", flag.ExitOnError)
		configPath := buildCmd.String("config", "", "Path to configuration file (ms.yml)")
		outdir := buildCmd.String("outdir", "", "Output directory")
		stopAfter := buildCmd.String("stop-after", "", "Print output and stop after stage: tokens, ast, go")

		buildCmd.Parse(os.Args[2:])

		if *configPath != "" && *outdir != "" {
			fmt.Println("Error: -config cannot be used with -outdir")
			buildCmd.Usage()
			return
		}

		var filename string
		if buildCmd.NArg() >= 1 {
			filename = buildCmd.Arg(0)
		}

		cfg, err := resolveConfig(*configPath, filename)
		if err != nil {
			fmt.Printf("Error loading config: %v\n", err)
			return
		}

		if *outdir != "" {
			cfg.CompilerOptions.OutputDir = *outdir
		}

		opts := compile.CompileOptions{StopAfter: *stopAfter}
		result := compile.Compile(filename, cfg, opts)
		if result.Error != nil {
			fmt.Printf("Error: %v\n", result.Error)
			return
		}

		if *stopAfter != "" {
			fmt.Printf("Stopped after %s\n", *stopAfter)
		}
		return
	}

	// Direct run mode: msc file.ms
	filename := os.Args[1]
	cfg, err := config.LoadConfig(filepath.Dir(filename))
	if err != nil {
		fmt.Printf("Error loading config: %v\n", err)
		return
	}

	opts := compile.CompileOptions{Run: true}
	result := compile.Compile(filename, cfg, opts)
	if result.Error != nil {
		fmt.Printf("Error: %v\n", result.Error)
	}
}

func resolveConfig(configPath, filename string) (*config.MsConfig, error) {
	if configPath != "" {
		return config.LoadConfig(configPath)
	}
	if filename != "" {
		return config.LoadConfig(filepath.Dir(filename))
	}
	return config.DefaultConfig(), nil
}
