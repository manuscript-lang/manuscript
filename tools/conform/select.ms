// Which fixtures a corpus command looks at: `--tag`, `--exclude-tag`, `--phase`, `--id`
// and `--shard i/n`.
import (
	Args, many, one from "./args.ms",
	Fixture, fixtures from "./corpus.ms",
)

PHASES List[String] := ["parse", "check", "run", "test"]

export type Filter:
	tags List[String]
	exclude_tags List[String]
	phases List[String]
	ids List[String]
	shard_index Int
	shard_count Int
	problem String

export fn filter_of(args Args) Filter:
	var filter = Filter(
		tags: many(args, "tag"),
		exclude_tags: many(args, "exclude-tag"),
		phases: many(args, "phase"),
		ids: many(args, "id"),
		shard_index: 0,
		shard_count: 1,
		problem: "",
	)
	for phase in filter.phases:
		if not PHASES.contains(phase): filter.problem = f"unknown phase {phase}"

	shard := one(args, "shard", "")

	if shard != "":
		slash := shard.index_of("/") or (-1)
		index := if slash < 0: -1 else: shard.slice(0, slash).parse_int() or (-1)
		count := if slash < 0: 0 else: shard.slice(
			slash + 1,
			shard.length(),
		).parse_int() or 0

		if index < 0 or count < 1 or index >= count: filter.problem = "--shard wants i/n with 0 <= i < n"
		else:
			filter.shard_index = index
			filter.shard_count = count

	return filter

fn wanted(fx Fixture, filter Filter) Bool:
	if not filter.tags.is_empty():
		var any = false
		for tag in fx.tags:
			if filter.tags.contains(tag): any = true
		if not any: return false

	for tag in fx.tags:
		if filter.exclude_tags.contains(tag): return false
	return true

// The fixtures under `root` that `filter` selects, in id order.
export fn select(root String, filter Filter) List[Fixture]:
	var phases = filter.phases.clone()
	if phases.is_empty(): phases = PHASES.clone()

	var found = List[Fixture]()
	for phase in phases:
		for fx in fixtures(root, phase, filter.ids):
			if wanted(fx, filter): found.append(fx.clone())
	found = found.sorted_by_key(fn fx: fx.id)
	if filter.shard_count == 1: return found

	var mine = List[Fixture]()
	for index in 0..found.length():
		if index % filter.shard_count == filter.shard_index: mine.append(
			found[index].clone()
		)
	return mine
