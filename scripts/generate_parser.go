package main

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
)

func main() {
	antlrVersion := "4.13.1"
	antlrJar := fmt.Sprintf("antlr-%s-complete.jar", antlrVersion)
	buildDir := filepath.Join("build")
	antlrJarPath := filepath.Join(buildDir, antlrJar)

	// Ensure the build directory exists
	if _, err := os.Stat(buildDir); os.IsNotExist(err) {
		if err := os.Mkdir(buildDir, 0755); err != nil {
			log.Fatalf("Failed to create build directory: %v", err)
		}
	}

	// Download ANTLR jar if it doesn't exist
	if _, err := os.Stat(antlrJarPath); os.IsNotExist(err) {
		fmt.Printf("Downloading ANTLR %s...\n", antlrVersion)
		err := downloadFile(antlrJarPath, fmt.Sprintf("https://www.antlr.org/download/%s", antlrJar))
		if err != nil {
			log.Fatalf("Failed to download ANTLR jar: %v", err)
		}
	}

	// Generate parser
	fmt.Println("Generating parser from grammar...")
	grammarDir := filepath.Join("internal", "grammar")
	parserOutputDir := filepath.Join("internal", "parser")
	grammarFile := "Manuscript.g4"

	cmd := exec.Command("java", "-jar", antlrJarPath, "-o", parserOutputDir, "-Dlanguage=Go", "-package", "parser", grammarFile)
	cmd.Dir = grammarDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		log.Fatalf("Failed to generate parser: %v", err)
	}

	fmt.Println("Done!")
}

// downloadFile downloads a file from the given URL and saves it to the specified path
func downloadFile(filepath string, url string) error {
	// Create the file
	out, err := os.Create(filepath)
	if err != nil {
		return err
	}
	defer out.Close()

	// Get the data
	resp, err := http.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	// Check server response
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("bad status: %s", resp.Status)
	}

	// Write the body to file
	_, err = io.Copy(out, resp.Body)
	return err
}
