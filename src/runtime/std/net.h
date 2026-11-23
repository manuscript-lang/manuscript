/* runtime/std/net.h: the @std/net natives that need neither the scheduler nor the event loop: IP addresses,
 * CIDR ranges and the diagnostic texts (net.c over net_ip.c). IpAddress and Cidr are copyable runtime
 * objects. Failures are MS_STATUS_* codes; the error slot is never written (no parse failure carries text).
 */
#ifndef MS_RUNTIME_STD_NET_H
#define MS_RUNTIME_STD_NET_H

#include "abi/status.h"
#include "base/desc.h"
#include "base/string.h"

/* ms-sig: msstd_net_parse_ip(text: *const StrVal, out: *mut *mut ObjCell<Ip>, err: ErrSlot) -> u8
 * @domain=network @end */
uint8_t msstd_net_parse_ip(const MsString *text, MsObj **out, MsString *err);
/* ms-sig: msstd_net_parse_cidr(text: *const StrVal, out: *mut *mut ObjCell<Cidr>, err: ErrSlot) -> u8
 * @domain=network @end */
uint8_t msstd_net_parse_cidr(const MsString *text, MsObj **out, MsString *err);
/* The JSON decoders: the same parse without an error text. */
/* ms-sig: msstd_json_dec_ip(text: *const StrVal, out: *mut *mut ObjCell<Ip>) -> u8 @domain=JSON @end */
uint8_t msstd_json_dec_ip(const MsString *text, MsObj **out);
/* ms-sig: msstd_json_dec_cidr(text: *const StrVal, out: *mut *mut ObjCell<Cidr>) -> u8 @domain=JSON @end */
uint8_t msstd_json_dec_cidr(const MsString *text, MsObj **out);
/* ms-sig: msstd_net_contains_ip(handle cidr: *const ObjCell<Cidr>, handle ip: *const ObjCell<Ip>, out: *mut
 * u8)
 * -> u8 @domain=network @end */
uint8_t msstd_net_contains_ip(const MsObj *cidr, const MsObj *ip, uint8_t *out);
/* ms-sig: msstd_net_ip_address_text(handle ip: *const ObjCell<Ip>, out: *mut StrVal) @domain=network @end */
void msstd_net_ip_address_text(const MsObj *ip, MsString *out);
/* IPv4 is 0, IPv6 is 1. */
/* ms-sig: msstd_net_ip_address_family(handle ip: *const ObjCell<Ip>) -> u8 @domain=network @end */
uint8_t msstd_net_ip_address_family(const MsObj *ip);
/* ms-sig: msstd_net_cidr_text(handle cidr: *const ObjCell<Cidr>, out: *mut StrVal) @domain=network @end */
void msstd_net_cidr_text(const MsObj *cidr, MsString *out);
/* ms-sig: msstd_net_ip_family_text(family: u8, out: *mut StrVal) @domain=network @end */
void msstd_net_ip_family_text(uint8_t family, MsString *out);
/* The DnsKind case index (A, AAAA, CNAME, MX, NS, TXT, PTR, SRV); empty for an unknown index. */
/* ms-sig: msstd_net_dns_kind_text(kind: u8, out: *mut StrVal) @domain=network @end */
void msstd_net_dns_kind_text(uint8_t kind, MsString *out);
/* NetworkError.message(): the Failed text verbatim, else "network: <reason>". */
/* ms-sig: msstd_net_error_message(status: u8, has_failed: u8, failed: *const StrVal, out: *mut StrVal)
 * @domain=network @end */
void msstd_net_error_message(uint8_t status, uint8_t has_failed, const MsString *failed, MsString *out);

#endif
