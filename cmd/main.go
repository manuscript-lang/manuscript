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
	if len(os.Args) > 1 && os.Args[1] == "build" {
		handleBuildCommand()
		return
	}

	if len(os.Args) != 2 {
		fmt.Println("Usage: msc <file.ms> or msc build [options] [file.ms]")
		return
	}

	// 1. Parse CLI options (filename from args)
	filename := os.Args[1]

	// 2. Resolve config file contents (search from source file directory)
	sourceDir := filepath.Dir(filename)
	cfg, err := config.LoadConfig(sourceDir)
	if err != nil {
		fmt.Printf("Error loading config: %v\n", err)
		return
	}

	// 3. Config object is constructed, now pass to compile pipeline
	compile.RunFile(filename, cfg)
}

func handleBuildCommand() {
	// 1. Parse CLI options
	buildCmd := flag.NewFlagSet("build", flag.ExitOnError)
	configPath := buildCmd.String("config", "", "Path to configuration file (ms.yml)")
	outdir := buildCmd.String("outdir", "", "Output directory")
	debug := buildCmd.Bool("d", false, "Print token stream")
	sourcemap := buildCmd.Bool("sourcemap", false, "Generate source maps")
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

	// 2. Resolve config file contents
	cfg, err := resolveConfig(configPath, filename)
	if err != nil {
		fmt.Printf("Error loading config: %v\n", err)
		return
	}

	// Override with command line options
	if *outdir != "" {
		cfg.CompilerOptions.OutputDir = *outdir
	}

	// 3. Config object is constructed, now pass to compile pipeline
	if *sourcemap {
		compile.BuildFileWithSourceMap(filename, cfg, *debug, cfg.CompilerOptions.OutputDir)
	} else {
		compile.BuildFile(filename, cfg, *debug)
	}
}

func resolveConfig(configPath *string, filename string) (*config.MsConfig, error) {
	var cfg *config.MsConfig
	var err error

	if *configPath != "" {
		// Load specific config file
		cfg, err = config.LoadConfig(*configPath)
	} else if filename != "" {
		// Search for config starting from source file directory
		sourceDir := filepath.Dir(filename)
		cfg, err = config.LoadConfig(sourceDir)
	} else {
		// Use default config
		cfg = config.DefaultConfig()
	}

	if err != nil {
		return nil, err
	}
	return cfg, nil
}
