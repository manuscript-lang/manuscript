import {bench_string} from "./strings.ms"
import {bench_list} from "./lists.ms"
import {bench_map_set} from "./maps.ms"
import {bench_json} from "./jsonbench.ms"
import {bench_csv} from "./csvbench.ms"
import {bench_binary} from "./binarybench.ms"
import {bench_regex} from "./regexbench.ms"
import {bench_path_url_math} from "./pathurl.ms"

# Standard-library micro-benchmarks. Each case prints `name<TAB>ops<TAB>ns_per_op`.
# Run with scripts/stdlib-bench.sh. Add a case with one `bench(...)` call in the matching module file.
export fn main() -> Int:
    bench_string()
    bench_list()
    bench_map_set()
    bench_json()
    bench_csv()
    bench_binary()
    bench_regex()
    bench_path_url_math()
    return 0
