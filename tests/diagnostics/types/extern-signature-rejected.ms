// conform: tags=diagnostics,functions,tier-core
// conform: phase=check
// conform: origin=ms_abi.h signature table
extern type Handle

enum Wrong {
	Detail(reason String)
}

enum Fine {
	Failed(code Int, message String)
}

extern fn takes_map(values Map[String, Int]) Void

extern fn returns_optional() Int?

extern fn nested_list(values List[List[Int]]) Void

extern fn wrong_error() Handle!Wrong

extern fn takes_closure(f fn(Map[String, Int]) Int) Void

extern fn returns_handle(f fn() Handle) Void

extern fn fine(h Handle, data List[Handle], each fn(Handle, Int8) String) Handle!Fine
// expect-error: MS3000 14:21 extern parameter values has type Map, which cannot cross the native boundary; an extern takes sized numbers, Bool, String, Bytes, extern types this program declares, Lists of them, and functions of them
// expect-error: MS3000 16:30 extern result has type Optional, which cannot cross the native boundary; an extern returns sized numbers, Bool, String, Bytes, extern types this program declares, and Lists of them, Void, or a Result of one
// expect-error: MS3000 18:23 extern parameter values has type List, which cannot cross the native boundary; an extern takes sized numbers, Bool, String, Bytes, extern types this program declares, Lists of them, and functions of them
// expect-error: MS3000 20:25 extern error type Wrong must be an alternative whose cases carry nothing, `code Int`, `message String`, or both; the native returns the status 1 + the case index and fills code_out and message_out
// expect-error: MS3000 22:25 extern parameter f has type fn(Map[String, Int]) Int, which cannot cross the native boundary; a function an extern takes has at most 6 parameters of sized numbers, Bool, String, Bytes or extern types this program declares, and returns a number, Bool, String, Bytes or Void
// expect-error: MS3000 24:26 extern parameter f has type fn() Handle, which cannot cross the native boundary; a function an extern takes has at most 6 parameters of sized numbers, Bool, String, Bytes or extern types this program declares, and returns a number, Bool, String, Bytes or Void
