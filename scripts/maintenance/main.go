// maintenance updates pinned inputs and the reproducible dependency license inventory.
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"github.com/manuscript-lang/manuscript/scripts/internal/devtool"
	"io"
	"io/fs"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

const inventoryPath = "documentation/contributing/dependency-licenses.json"

type notice struct {
	Path   string `json:"path"`
	SHA256 string `json:"sha256"`
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
func run(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("usage: maintenance licenses [-check] | vendor | go <version> | node <version> | version <version>")
	}
	switch args[0] {
	case "licenses":
		if len(args) > 2 || len(args) == 2 && args[1] != "-check" {
			return fmt.Errorf("usage: maintenance licenses [-check]")
		}
		return licenses(len(args) == 2)
	case "vendor":
		if len(args) != 1 {
			return fmt.Errorf("usage: maintenance vendor")
		}
		if err := command("", devtool.Go(), "mod", "tidy"); err != nil {
			return err
		}
		if err := command("", devtool.Go(), "mod", "vendor"); err != nil {
			return err
		}
		return licenses(false)
	case "go", "node", "version":
		if len(args) != 2 || !regexp.MustCompile(`^\d+\.\d+\.\d+$`).MatchString(args[1]) {
			return fmt.Errorf("provide an exact version, for example maintenance %s 1.25.1", args[0])
		}
		if args[0] == "go" {
			return updateGo(args[1])
		}
		if args[0] == "version" {
			data, err := os.ReadFile("CHANGELOG.md")
			if err != nil {
				return err
			}
			heading := "## Unreleased"
			if !strings.Contains(string(data), heading) {
				return fmt.Errorf("CHANGELOG.md needs an Unreleased section")
			}
			replacement := heading + "\n\n## " + args[1]
			if err := os.WriteFile("CHANGELOG.md", []byte(strings.Replace(string(data), heading, replacement, 1)), 0644); err != nil {
				return err
			}
			return os.WriteFile(".msversion", []byte(args[1]+"\n"), 0644)
		}
		if err := os.WriteFile(".node-version", []byte(args[1]+"\n"), 0644); err != nil {
			return err
		}
		fmt.Println("Node pin updated. Install this version, then run npm ci in extensions/vscode and make verify-full.")
		return nil
	default:
		return fmt.Errorf("unknown maintenance command %q", args[0])
	}
}

func command(dir, name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
func licenses(check bool) error {
	var notices []notice
	for _, root := range []string{"vendor", "website/themes/hugo-book", "skills"} {
		err := filepath.WalkDir(root, func(path string, e fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if e.IsDir() {
				return nil
			}
			name := strings.ToUpper(e.Name())
			if !strings.HasPrefix(name, "LICENSE") && !strings.HasPrefix(name, "COPYING") && !strings.HasPrefix(name, "PATENTS") {
				return nil
			}
			data, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			sum := sha256.Sum256(data)
			notices = append(notices, notice{filepath.ToSlash(path), hex.EncodeToString(sum[:])})
			return nil
		})
		if err != nil {
			return err
		}
	}
	sort.Slice(notices, func(i, j int) bool { return notices[i].Path < notices[j].Path })
	data, err := json.MarshalIndent(notices, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	if check {
		actual, err := os.ReadFile(inventoryPath)
		if err != nil {
			return err
		}
		if !bytes.Equal(actual, data) {
			return fmt.Errorf("dependency notices changed; run make licenses")
		}
		return nil
	}
	return os.WriteFile(inventoryPath, data, 0644)
}

type release struct {
	Version string                                              `json:"version"`
	Files   []struct{ Filename, OS, Arch, SHA256, Kind string } `json:"files"`
}

func updateGo(version string) error {
	client := http.Client{Timeout: 30 * time.Second}
	response, err := client.Get("https://go.dev/dl/?mode=json&include=all")
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("Go release catalog: %s", response.Status)
	}
	var releases []release
	if err := json.NewDecoder(io.LimitReader(response.Body, 16<<20)).Decode(&releases); err != nil {
		return err
	}
	targets := map[string]bool{"linux/amd64": true, "linux/arm64": true, "darwin/amd64": true, "darwin/arm64": true, "windows/amd64": true, "windows/arm64": true}
	var lines []string
	for _, release := range releases {
		if release.Version != "go"+version {
			continue
		}
		for _, file := range release.Files {
			target := file.OS + "/" + file.Arch
			if file.Kind != "archive" || !targets[target] {
				continue
			}
			if len(file.SHA256) != 64 {
				return fmt.Errorf("invalid checksum for %s", file.Filename)
			}
			lines = append(lines, file.SHA256+"  "+file.Filename)
			delete(targets, target)
		}
	}
	if len(targets) != 0 {
		return fmt.Errorf("Go %s does not supply all six supported targets", version)
	}
	sort.Strings(lines)
	parts := strings.Split(version, ".")
	if err := command("", devtool.Go(), "mod", "edit", "-go="+parts[0]+"."+parts[1]+".0"); err != nil {
		return err
	}
	if err := os.WriteFile("scripts/toolchains.sha256", []byte(strings.Join(lines, "\n")+"\n"), 0644); err != nil {
		return err
	}
	if err := os.WriteFile(".go-version", []byte(version+"\n"), 0644); err != nil {
		return err
	}
	fmt.Println("Go pin and six archive checksums updated. Run make setup, make vendor-refresh, and make verify-full.")
	return nil
}
