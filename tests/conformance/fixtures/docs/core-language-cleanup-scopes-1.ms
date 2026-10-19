# conform: tags=parser,tier-core,try-result,with-cleanup
# conform: phase=parse
# conform: origin=documentation/core-language/cleanup/scopes.md:10
with file = try files.open("data.txt"):
    let chunk = try file.read(max_bytes: 4096)
