from pathlib import Path
import shutil
root=Path('/workspace/manuscript');target=Path('/tmp/manuscript-focused-stdlib')
if target.exists():shutil.rmtree(target)
shutil.copytree(root/'bench/perf/stdlib',target)
p=target/'src/harness.ms';s=p.read_text().replace('import range from','import arguments from "@std/process.ms"\nimport range from',1)
start=s.index('    let started =',s.index('export fn bench('));end=s.index('\nexport fn ints(',start)
s=s[:start]+'''    let selected = arguments().get(0, "")
    if selected != name: return
    var sample = 0
    while sample < 20:
        let started = clock().now()
        let checksum = body()
        let elapsed = clock().now().difference(started).to_nanoseconds()
        say("{name}\\t{ops}\\t{elapsed / ops}\\n")
        say("# checksum {name} {checksum}\\n")
        sample += 1
''' +s[end:];p.write_text(s)
(target/'src/main.ms').write_text('''import arguments from "@std/process.ms"
import bench_string from "./strings.ms"
import bench_map_set from "./maps.ms"
import bench_regex from "./regexbench.ms"
import bench_host from "./hostbench.ms"
export fn main() Int:
    let name = arguments().get(0, "")
    if name.starts_with("string."): bench_string()
    if name.starts_with("map."): bench_map_set()
    if name.starts_with("regex."): bench_regex()
    if name.starts_with("archive."): bench_host()
    return 0
''')
