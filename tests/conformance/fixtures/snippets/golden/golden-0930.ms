// conform: tags=diagnostics
// conform: phase=check
interface Read {
    case Ready
}
// expect-error: MS1000 4:5-4:9 an interface contains only operation signatures; write 'fn name(...) Type' and write each method body beside the type that provides it, as 'fn Type.name(...)'
