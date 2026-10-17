# Standard-library benchmark results

Output of `make stdlib-bench` (5 repeats, median ns/op) at `88a6360` on 2026-10-17.
Machine: 4 vCPU linux/amd64 cloud container. Compare only against numbers from the same machine; this is a profiling guide, not a gate.

```
case                            median ns/op       min       max
string.append_builder                      7         6        11
string.concat                           3166      3045      3552
string.split                           29488     27973     35197
string.replace_all                     72829     58816     83424
string.contains                         6497      5575      7506
string.upper                           69155     63737    109936
string.trim                               14        13        18
string.index_char_at                       7         6        12
string.chars                          207777    140850    259043
string.parse_int                          27        21        37
string.interpolate                       124       121       169
list.append                               65        58       121
list.at                                    3         2         4
list.for_in                                1         0         1
list.map                                   8         5        11
list.filter                               23         9        27
list.fold                                  4         3        12
list.sorted                              166       136       209
list.contains                         349776    310207    456253
list.distinct                             36        24        39
list.concat_reverse                       32        29        92
list.records_map                          48        30        51
map.int_put_get                          174       154       240
map.string_put_get                        98        45       129
map.iterate_entries                      386       346       403
set.add_contains                         125        76       152
json.parse                              1957      1449      2261
json.roundtrip                          3071      2513      3597
csv.stringify                            348       333      1103
csv.parse                                437       197       487
encoding.base64_encode                     5         1         8
encoding.base64_decode                     3         1        23
encoding.hex_encode                        3         2         7
crypto.sha256                              0         0         1
bytes.builder                              8         4        12
regex.find_all                           618       248      1034
regex.matches                            116       106       173
regex.replace_all                        280       244       342
path.join_normalize                      931       797      1240
path.basename                             20        17        22
url.parse                                599       493       771
url.encode_component                     200       175       293
math.sqrt_sin                              7         7        14
yaml.parse                             12320     10773     14021
yaml.roundtrip                         17263     16057     22323
toml.parse                              9338      7396      9936
html.parse                              2608      2107      3733
html.escape_unescape                     169       104       421
bigint.factorial_1000                    295       257       919
decimal.add_round                       2154      1936      2425
compress.gzip                              5         3         6
compress.roundtrip                         7         4        13
time.parse_timestamp                     496       383       649
queue.enqueue_dequeue                     16        13        30
priority_queue.enqueue_dequeue           314       289       356
archive.zip_pack                        1765      1511      2982
archive.tar_pack                        5943      5146     11019
archive.zip_unpack                     16621     12874     21554
sse.feed                                2635      1685      2857
time.timestamp_to_string                 100        96       180
random.uuid_v4                           837       554      1005
fs.write_file_64k                     169379    147550    214125
fs.read_file_64k                       71132     59575     87734
fs.stat                                 7681      6369     10678
fs.list_200                           171945    136330    204699
log.info                                6235      5365      7441

real	1m28.900s
user	2m23.552s
sys	0m31.667s
```
