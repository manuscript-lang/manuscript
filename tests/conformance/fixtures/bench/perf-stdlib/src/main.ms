import (
	bench_binary from "./binarybench.ms",
	bench_csv from "./csvbench.ms",
	bench_fs from "./fsbench.ms",
	bench_host from "./hostbench.ms",
	bench_html from "./htmlbench.ms",
	bench_json from "./jsonbench.ms",
	bench_list from "./lists.ms",
	bench_map_set from "./maps.ms",
	bench_numbers from "./numbers.ms",
	bench_path_url_math from "./pathurl.ms",
	bench_regex from "./regexbench.ms",
	bench_string from "./strings.ms",
	bench_toml from "./tomlbench.ms",
	bench_yaml from "./yamlbench.ms",
)

// Standard-library micro-benchmarks. Each case prints `name<TAB>ops<TAB>ns_per_op`. Run
// with bench/perf/tools/stdlib_bench.ms. Add a case with one `bench(...)` call in the
// matching module file.
fn main() Void {
	bench_string()
	bench_list()
	bench_map_set()
	bench_json()
	bench_csv()
	bench_binary()
	bench_regex()
	bench_path_url_math()
	bench_yaml()
	bench_toml()
	bench_html()
	bench_numbers()
	bench_host()
	bench_fs()
}
