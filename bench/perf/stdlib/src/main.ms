import {bench_string} from "./strings.ms"
import {bench_list} from "./lists.ms"
import {bench_map_set} from "./maps.ms"
import {bench_structures} from "./structures.ms"
import {bench_json} from "./jsonbench.ms"
import {bench_csv} from "./csvbench.ms"
import {bench_binary} from "./binarybench.ms"
import {bench_regex} from "./regexbench.ms"
import {bench_path_url_math} from "./pathurl.ms"
import {bench_yaml} from "./yamlbench.ms"
import {bench_toml} from "./tomlbench.ms"
import {bench_html} from "./htmlbench.ms"
import {bench_numbers} from "./numbers.ms"
import {bench_host} from "./hostbench.ms"
import {bench_fs} from "./fsbench.ms"

# Standard-library micro-benchmarks. Each case prints `name<TAB>ops<TAB>ns_per_op`.
# Run with bench/perf/stdlib-bench.sh. Add a case with one `bench(...)` call in the matching module file.
export fn main() Int:
    bench_string()
    bench_list()
    bench_map_set()
    bench_structures()
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
