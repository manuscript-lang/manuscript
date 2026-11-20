/* The datagram natives, declared here until the standard library switches to them: the switch moves these
 * declarations to ms_rt/net.h and lists the symbols in runtime/symbols/net.txt (the symbols check rejects duplicates of
 * the Rust definitions before then). */
#ifndef MS_NET_DATAGRAM_H
#define MS_NET_DATAGRAM_H

#include "ms_rt/base.h"
#include "ms_rt/string.h"

/* Datagram sockets (DgramH): a UDP socket bound to a literal address. Addresses are text, "1.2.3.4:80"; a name is
 * resolved by the caller. `receive` waits for one datagram of at most `max` bytes (1 to 65535, default 65535): a longer
 * one is dropped and gives STATUS_LIMIT_EXCEEDED. `send` gives STATUS_LIMIT_EXCEEDED for more than 65535 bytes.
 * `close` ends all use at once; a call blocked in a wait ends by its deadline or cancellation. Handles follow the
 * connection handles: `share` is another end, `close_if_last` closes when no other end is open. */
typedef struct MsNetDatagram {
    MsVec data;
    MsStr sender;
} MsNetDatagram;

/* ms-sig: msstd_dgram_bind(address: *const StrVal, out: *mut *mut ObjCell<DgramH>, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_dgram_bind(const MsStr *address, void **out, MsStr *err);
/* ms-sig: msstd_dgram_address(handle s: *const ObjCell<DgramH>, out: *mut StrVal) @domain=network */
void msstd_dgram_address(const void *handle, MsStr *out);
/* ms-sig: msstd_dgram_close(handle s: *const ObjCell<DgramH>) @domain=network */
void msstd_dgram_close(const void *handle);
/* ms-sig: msstd_dgram_share(handle s: *const ObjCell<DgramH>) -> *mut ObjCell<DgramH> @handle @domain=network */
void *msstd_dgram_share(const void *handle);
/* ms-sig: msstd_dgram_close_if_last(handle s: *const ObjCell<DgramH>) @domain=network */
void msstd_dgram_close_if_last(const void *handle);
/* ms-sig: msstd_dgram_receive(handle s: *const ObjCell<DgramH>, has_max: HasRaw, max: i64, has_timeout: HasRaw, timeout: i64, out: *mut DatagramWire, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_dgram_receive(const void *handle, uint8_t has_max, int64_t max, uint8_t has_timeout, int64_t timeout, MsNetDatagram *out, MsStr *err);
/* ms-sig: msstd_dgram_send(handle s: *const ObjCell<DgramH>, data: *const VecVal, address: *const StrVal, has_timeout: HasRaw, timeout: i64, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_dgram_send(const void *handle, const MsVec *data, const MsStr *address, uint8_t has_timeout, int64_t timeout, MsStr *err);

#endif
