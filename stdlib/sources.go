// Package stdlib supplies the authoritative, source-addressable standard APIs.
package stdlib

import (
	"embed"
	"os"
	"path/filepath"
)

// Sources is pinned with the compiler and can be materialized for editors.
//
//go:embed *.ms bindings.json
var Sources embed.FS

// Materialize writes the pinned declaration files for an editor that requires
// ordinary filesystem URIs rather than virtual @std document identities.
func Materialize(directory string) error {
	if err := os.MkdirAll(directory, 0755); err != nil {
		return err
	}
	entries, err := Sources.ReadDir(".")
	if err != nil {
		return err
	}
	for _, entry := range entries {
		data, err := Sources.ReadFile(entry.Name())
		if err != nil {
			return err
		}
		temp, err := os.CreateTemp(directory, ".stdlib-*")
		if err != nil {
			return err
		}
		name := temp.Name()
		if _, err = temp.Write(data); err != nil {
			temp.Close()
			os.Remove(name)
			return err
		}
		if err = temp.Close(); err != nil {
			os.Remove(name)
			return err
		}
		if err = os.Chmod(name, 0644); err != nil {
			os.Remove(name)
			return err
		}
		if err = os.Rename(name, filepath.Join(directory, entry.Name())); err != nil {
			os.Remove(name)
			return err
		}
	}
	return nil
}
