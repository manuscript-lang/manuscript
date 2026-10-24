from "./strings.ms" import bench_string
from "./lists.ms" import bench_list
from "./maps.ms" import bench_map_set
from "./jsonbench.ms" import bench_json
from "./csvbench.ms" import bench_csv
from "./binarybench.ms" import bench_binary
from "./regexbench.ms" import bench_regex
from "./pathurl.ms" import bench_path_url_math
from "./yamlbench.ms" import bench_yaml
from "./tomlbench.ms" import bench_toml
from "./htmlbench.ms" import bench_html
from "./numbers.ms" import bench_numbers
from "./hostbench.ms" import bench_host
from "./fsbench.ms" import bench_fs

# Standard-library micro-benchmarks. Each case prints `name<TAB>ops<TAB>ns_per_op`.
# Run with bench/perf/stdlib-bench.sh. Add a case with one `bench(...)` call in the matching module file.
export def main() -> Int:
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
    return 0
