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
		handleBuildCommand()
		return
	}

	filename := os.Args[1]
	cfg, err := loadConfigFromFile(filename)
	if err != nil {
		fmt.Printf("Error loading config: %v\n", err)
		return
	}

	compile.RunFile(filename, cfg)
}

func handleBuildCommand() {
	buildCmd := flag.NewFlagSet("build", flag.ExitOnError)
	configPath := buildCmd.String("config", "", "Path to configuration file (ms.yml)")
	outdir := buildCmd.String("outdir", "", "Output directory")
	debug := buildCmd.Bool("d", false, "Print token stream")
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

	compile.BuildFile(filename, cfg, *debug)
}

func loadConfigFromFile(filename string) (*config.MsConfig, error) {
	return config.LoadConfig(filepath.Dir(filename))
}

func resolveConfig(configPath, filename string) (*config.MsConfig, error) {
	if configPath != "" {
		return config.LoadConfig(configPath)
	}
	if filename != "" {
		return loadConfigFromFile(filename)
	}
	return config.DefaultConfig(), nil
}
