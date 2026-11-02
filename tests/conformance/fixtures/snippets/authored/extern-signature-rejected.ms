# conform: tags=diagnostics,functions,tier-core
# conform: phase=check
# conform: origin=ms_abi.h signature table
extern type Handle

type Wrong:
    case Detail(reason: String)

type Fine:
    case Failed(code: Int, message: String)

extern fn takes_map(values: Map[String, Int]) Unit
extern fn returns_optional() Int?
extern fn nested_list(values: List[List[Int]]) Unit
extern fn wrong_error() Handle!Wrong
extern fn takes_closure(f: fn() Int) Unit
extern fn fine(h: Handle, data: List[Handle]) Handle!Fine
