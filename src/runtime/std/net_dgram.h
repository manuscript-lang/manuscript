/* runtime/std/net_dgram.h: the datagram natives of @std/net (net_dgram.c). */
#ifndef MS_RUNTIME_STD_NET_DGRAM_H
#define MS_RUNTIME_STD_NET_DGRAM_H

#include "abi/status.h"
#include "base/bytes.h"
#include "base/desc.h"
#include "base/string.h"

/* What a receive returns: the payload and the sender's "ip:port". */
typedef struct MsDatagramWire {
  MsBytes data;
  MsString sender;
} MsDatagramWire;

/* ms-sig: msstd_net_datagram_receive(handle sock: *const ObjCell<DgramH>, has_max: HasRaw, max: i64, has_timeout: HasRaw, timeout: i64, out: *mut DatagramWire, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_datagram_receive(const MsObj *handle, uint8_t has_max, int64_t max, uint8_t has_timeout,
                                   int64_t timeout, MsDatagramWire *out, MsString *err);
/* ms-sig: msstd_net_datagram_send_bytes(handle sock: *const ObjCell<DgramH>, data: *const VecVal, address: *const StrVal, has_timeout: HasRaw, timeout: i64, err: ErrSlot) -> u8 @domain=network */
uint8_t msstd_net_datagram_send_bytes(const MsObj *handle, const MsBytes *data, const MsString *address,
                                      uint8_t has_timeout, int64_t timeout, MsString *err);
/* ms-sig: msstd_net_datagram_address(handle sock: *const ObjCell<DgramH>, out: *mut StrVal) @domain=network */
void msstd_net_datagram_address(const MsObj *handle, MsString *out);
/* ms-sig: msstd_net_datagram_close(handle sock: *const ObjCell<DgramH>) @domain=network */
void msstd_net_datagram_close(const MsObj *handle);
/* ms-sig: msstd_net_datagram_close_if_last(handle sock: *const ObjCell<DgramH>) @domain=network */
void msstd_net_datagram_close_if_last(const MsObj *handle);
/* ms-sig: msstd_net_datagram_share(handle sock: *const ObjCell<DgramH>) -> *mut ObjCell<DgramH> @handle @domain=network */
MsObj *msstd_net_datagram_share(const MsObj *handle);

#endif
