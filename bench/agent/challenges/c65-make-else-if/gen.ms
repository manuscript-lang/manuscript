// Generator for c65-make-else-if. The expected outputs come from the Go oracle in
// oracle/*.ref (built with the local Go toolchain). The hidden cases are the inputs of
// c56-make-lite (the behavior that must survive the edit) plus scenarios for chained
// conditionals. Deterministic; run: ms run bench/agent/gen.ms -- c65
import (
	JsonValue, parse from "@std/data/json.ms",

	root from "../../core/model.ms",
	Cases, build_oracle, write_cases from "../../lib/gen.ms",
	read_text from "../../lib/text.ms",
)

fn add(var cs: Cases, name: String, script: String) Void:
	cs.push(name, script)

// The entries of c56-make-lite's hidden cases.
fn c56_inputs() List[JsonValue]:
	doc := parse(read_text(f"{root()}/challenges/c56-make-lite/hidden/cases.json")).get_or(
		JsonValue.Null
	)
	return doc.as_list() or []

CHAIN := "ifeq ($(MODE),debug)\nX = debug\nelse ifeq ($(MODE),release)\nX = release\nelse ifdef FAST\nX = fast\nelse ifneq ($(Y),)\nX = y\nelse\nX = none\nendif\nall:\n\t@echo $(X)\n====\n====\n"

export fn gen_c65() Void:
	var cs = Cases(build_oracle("c65-make-else-if"))

	for entry in c56_inputs():
		name := (entry.get("name") or JsonValue.Null).as_string() or ""
		stdin := (entry.get("stdin") or JsonValue.Null).as_string() or ""
		add(cs, f"kept-{name}", stdin)

	add(
		cs,
		"chain-each-branch",
		CHAIN + "dry MODE=debug\ndry MODE=release\ndry FAST=1\ndry Y=1\ndry\n",
	)
	add(
		cs,
		"chain-first-wins",
		CHAIN + "dry MODE=debug FAST=1 Y=1\ndry MODE=release FAST=1\n",
	)
	add(
		cs,
		"chain-expand",
		"ifeq ($(A),1)\nX=a\nelse ifeq ($(A),2)\nX=b\nelse\nX=c\nendif\nA=2\n====\n====\nexpand $(X)\n",
	)
	add(
		cs,
		"chain-sees-earlier-vars",
		"A = 5\nifeq ($(A),1)\nX=one\nelse ifeq ($(A),5)\nB = 1\nelse ifdef B\nX=b\nendif\nifdef B\nY=defined\nendif\nall:\n\t@echo [$(X)] [$(Y)]\n====\n====\ndry\n",
	)
	add(
		cs,
		"chain-nested-inactive-parent",
		"ifdef NOPE\nifeq (a,b)\nX=1\nelse ifeq (a,a)\nX=2\nelse\nX=3\nendif\nelse\nX=4\nendif\nall:\n\t@echo [$(X)]\n====\n====\ndry\n",
	)
	add(
		cs,
		"chain-nested-active",
		"ifdef YES\nifeq (a,b)\nX=1\nelse ifeq (a,a)\nX=2\nelse\nX=3\nendif\nelse\nX=4\nendif\nall:\n\t@echo [$(X)]\n====\n====\ndry YES=1\ndry\n",
	)
	add(
		cs,
		"chain-skipped-bad-syntax-ok",
		"ifeq (a,a)\nX=1\nelse ifeq bad syntax\nX=2\nelse ifeq (a b c)\nX=3\nendif\nall:\n\t@echo $(X)\n====\n====\ndry\n",
	)
	add(
		cs,
		"chain-bad-syntax-evaluated",
		"ifeq (a,b)\nX=1\nelse ifeq bad\nX=2\nendif\nall:\n\t@echo $(X)\n====\n====\ndry\nfiles\n",
	)
	add(
		cs,
		"chain-bad-comma-evaluated",
		"ifeq (a,b)\nX=1\nelse ifneq (a,b,c)\nX=2\nendif\nall:\n\t@echo $(X)\n====\n====\ndry\n",
	)
	add(
		cs,
		"chain-info-not-run-when-skipped",
		"ifeq (a,a)\nX=1\nelse ifeq ($(info side effect),x)\nX=2\nendif\nall:\n\t@echo $(X)\n====\n====\ndry\n",
	)
	add(
		cs,
		"chain-info-runs-when-evaluated",
		"ifeq (a,b)\nX=1\nelse ifeq ($(info side effect),x)\nX=2\nelse\nX=3\nendif\nall:\n\t@echo $(X)\n====\n====\ndry\n",
	)
	add(
		cs,
		"chain-else-after-else",
		"ifeq (a,b)\nX=1\nelse\nX=2\nelse ifdef Z\nX=3\nendif\nall:\n\t@echo $(X)\n====\n====\ndry\n",
	)
	add(
		cs,
		"chain-double-else",
		"ifeq (a,b)\nX=1\nelse ifeq (a,c)\nX=2\nelse\nX=3\nelse\nX=4\nendif\nall:\n\t@echo $(X)\n====\n====\ndry\n",
	)
	add(
		cs,
		"chain-without-open-block",
		"else ifdef A\nX=1\nendif\nall:\n\t@echo hi\n====\n====\ndry\n",
	)
	add(
		cs,
		"chain-missing-endif",
		"ifdef A\nX=1\nelse ifdef B\nX=2\nelse ifdef C\nX=3\nall:\n\t@echo hi\n====\n====\ndry\n",
	)
	add(
		cs,
		"chain-missing-endif-inner",
		"ifdef A\nifdef B\nX=1\nelse ifdef C\nX=2\nendif\nall:\n\t@echo hi\n====\n====\ndry\n",
	)
	add(
		cs,
		"chain-in-rules",
		"all: a b\n\t@echo all\nifdef ONE\na:\n\t@echo a-one\nelse ifdef TWO\na:\n\t@echo a-two\nelse\na:\n\t@echo a-none\nendif\nb:\n\t@echo b\n====\n====\ndry ONE=1\ndry TWO=1\ndry\ntargets\n",
	)
	add(
		cs,
		"chain-ifndef",
		"ifndef A\nX=1\nelse ifndef B\nX=2\nelse ifndef C\nX=3\nelse\nX=4\nendif\nall:\n\t@echo $(X)\n====\n====\ndry A=1\ndry A=1 B=1\ndry A=1 B=1 C=1\ndry\n",
	)
	add(
		cs,
		"chain-else-text-ignored",
		"ifdef A\nX=1\nelse whatever\nX=2\nendif\nall:\n\t@echo $(X)\n====\n====\ndry\ndry A=1\n",
	)
	add(
		cs,
		"chain-tab-separated",
		"ifdef A\nX=1\nelse\tifdef B\nX=2\nelse\tifeq (x,x)\nX=3\nendif\nall:\n\t@echo $(X)\n====\n====\ndry\ndry B=1\n",
	)
	add(
		cs,
		"chain-comment-and-spaces",
		"ifdef A\nX=1\nelse   ifdef B   # why\nX=2\nelse ifeq ( x , x )\nX=3\nendif\nall:\n\t@echo $(X)\n====\n====\ndry\ndry B=1\n",
	)
	add(
		cs,
		"chain-elsewhere-word-not-directive",
		"ifdef A\nX=1\nelse ifdefined B\nX=2\nendif\nall:\n\t@echo [$(X)]\n====\n====\ndry\n",
	)

	examples := [
		cs.make(
			"ex-chain",
			"ifeq ($(MODE),debug)\nX = debug\nelse ifeq ($(MODE),release)\nX = release\nelse\nX = other\nendif\nall:\n\t@echo $(X)\n====\n====\ndry MODE=release\n",
		),
		cs.make(
			"ex-chain-error",
			"ifdef A\nX=1\nelse ifeq bad\nX=2\nendif\nall:\n\t@echo $(X)\n====\n====\ndry\ndry A=1\n",
		),
	]
	write_cases("c65-make-else-if", examples, cs.list)
