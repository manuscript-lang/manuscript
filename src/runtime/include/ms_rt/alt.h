/* ms_rt/alt.h: the predicates of Optional and Result, which have no C body: an `opt<T>` or `Result` has the layout
 * of its payload, which the runtime does not know, so the lowering writes each as the MIR in its tag. Declared here so
 * the method a stdlib declaration names (`Optional[T].is_some`) finds its row by name like every native. */
#ifndef MS_RT_ALT_H
#define MS_RT_ALT_H

#include "ms_rt/base.h"

/* ms: domain core */
/* ms-sig: msrt_optional_is_some(o: *const AltVal) -> u8 @inline @op=opt.is_some */
uint8_t msrt_optional_is_some(const void *o);
/* ms-sig: msrt_optional_is_none(o: *const AltVal) -> u8 @inline @seq=opt.is_some:$0>bool,not:%0>bool */
uint8_t msrt_optional_is_none(const void *o);
/* ms-sig: msrt_result_is_ok(r: *const AltVal) -> u8 @inline @seq=alt.tag:$0>int,iconst:#0>int,icmp.eq:%0:%1>bool */
uint8_t msrt_result_is_ok(const void *r);
/* ms-sig: msrt_result_is_error(r: *const AltVal) -> u8 @inline @seq=alt.tag:$0>int,iconst:#1>int,icmp.eq:%0:%1>bool */
uint8_t msrt_result_is_error(const void *r);

/* ms-sig: msrt_result_get_or(r: *const AltVal, fallback: *const AltVal) -> *const u8 @inline @fallback */
const void *msrt_result_get_or(const void *r, const void *fallback);

#endif
