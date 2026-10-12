package compiler

import (
	"encoding/json"
	"os"
	"os/exec"
	goruntime "runtime"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

type nodeHostInventory struct {
	Baseline string
	APIs     []struct {
		Module, API, Status, Reason string
		Targets                     []string
		Platforms                   []string
	}
}

func readNodeHostInventory(t *testing.T) nodeHostInventory {
	t.Helper()
	data, err := os.ReadFile("testdata/node-host-coverage.json")
	if err != nil {
		t.Fatal(err)
	}
	var inventory nodeHostInventory
	if err = json.Unmarshal(data, &inventory); err != nil {
		t.Fatal(err)
	}
	return inventory
}
func TestNodeHostCoverageMappings(t *testing.T) {
	inventory := readNodeHostInventory(t)
	if inventory.Baseline != "Node.js 24.19.0" {
		t.Fatal("missing compatibility baseline")
	}
	declarations := map[string]bool{}
	for _, module := range checker.StandardLibrary() {
		for _, declaration := range module.Declarations {
			key := module.Path + "/" + declaration.Name
			declarations[key] = true
			for _, operation := range declaration.Operations {
				name, _, _ := strings.Cut(operation, ":")
				declarations[key+"."+name] = true
			}
			for _, field := range declaration.Fields {
				name, _, _ := strings.Cut(field, ":")
				declarations[key+"."+name] = true
			}
		}
	}
	seen := map[string]bool{}
	modules := map[string]int{}
	for _, api := range inventory.APIs {
		key := api.Module + "/" + api.API
		if seen[key] {
			t.Errorf("duplicate API %s", key)
		}
		seen[key] = true
		modules[api.Module]++
		if api.Reason == "" {
			t.Errorf("missing classification rationale: %s", key)
		}
		switch api.Status {
		case "equivalent", "adapted":
			if len(api.Targets) == 0 {
				t.Errorf("missing mapping: %s", key)
			}
		case "runtime_specific":
		default:
			t.Errorf("unknown status: %s", key)
		}
		for _, target := range api.Targets {
			if !declarations[target] {
				t.Errorf("%s maps to absent declaration %s", key, target)
			}
		}
	}
	for _, module := range []string{"fs/promises", "os", "path", "process", "timers", "timers/promises"} {
		if modules[module] == 0 {
			t.Errorf("missing package %s", module)
		}
	}
}
func TestNodeHostInventoryContainsAllBaselineExports(t *testing.T) {
	node, err := exec.LookPath("node")
	if err != nil {
		t.Skip("offline coverage mapping checked; Node.js oracle not installed")
	}
	version, err := exec.Command(node, "--version").Output()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(string(version), "v24.") {
		t.Skip("live export check requires Node.js 24")
	}
	data, err := exec.Command(node, "-e", `console.log(JSON.stringify(Object.fromEntries(["fs/promises","os","path","process","timers","timers/promises"].map(m=>[m,Object.keys(require("node:"+m)).filter(k=>!k.startsWith("_")).sort()]))))`).Output()
	if err != nil {
		t.Fatal(err)
	}
	var exports map[string][]string
	if err = json.Unmarshal(data, &exports); err != nil {
		t.Fatal(err)
	}
	seen := map[string]bool{}
	for _, api := range readNodeHostInventory(t).APIs {
		seen[api.Module+"/"+api.API] = true
	}
	// Methods on returned resources are inventoried alongside module exports.
	resourceData, err := exec.Command(node, "-e", `(async()=>{const fs=require("node:fs/promises");const h=await fs.open("testdata/node-host-coverage.json","r");const handle=Object.getOwnPropertyNames(Object.getPrototypeOf(h)).filter(n=>n!=="constructor");handle.push("close");await h.close();const d=await fs.opendir("testdata");const dir=Object.getOwnPropertyNames(Object.getPrototypeOf(d)).filter(n=>!["constructor","processReadResult","readSyncRecursive"].includes(n));await d.close();const t=setTimeout(()=>{},10000);const timer=Object.getOwnPropertyNames(Object.getPrototypeOf(t)).filter(n=>n!=="constructor");clearTimeout(t);console.log(JSON.stringify({"fs/promises:FileHandle":handle,"fs:Dir":dir,"timers:Timeout":timer}));})().catch(e=>{console.error(e);process.exitCode=1})`).Output()
	if err != nil {
		t.Fatal(err)
	}
	var resources map[string][]string
	if err = json.Unmarshal(resourceData, &resources); err != nil {
		t.Fatal(err)
	}
	for module, names := range resources {
		exports[module] = names
	}
	for module, names := range exports {
		for _, name := range names {
			key := module + "/" + name
			if !seen[key] {
				t.Errorf("unclassified baseline export %s", key)
			}
			delete(seen, key)
		}
	}
	for _, api := range readNodeHostInventory(t).APIs {
		if len(api.Platforms) > 0 {
			available := false
			for _, platform := range api.Platforms {
				if platform == goruntime.GOOS {
					available = true
				}
			}
			if !available {
				delete(seen, api.Module+"/"+api.API)
			}
		}
	}
	for key := range seen {
		t.Errorf("inventory export absent from installed Node.js 24: %s", key)
	}
}
