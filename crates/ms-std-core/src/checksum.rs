//! CRC-32/ISO-HDLC for `@std/data/checksum.ms`.
use ms_rt::ffi::native;

const CRC_TABLE: [u32; 256] = {
    let mut t = [0u32; 256];
    let mut i = 0;
    while i < 256 {
        let mut c = i as u32;
        let mut k = 0;
        while k < 8 {
            c = if c & 1 != 0 {
                0xedb8_8320 ^ (c >> 1)
            } else {
                c >> 1
            };
            k += 1;
        }
        t[i] = c;
        i += 1;
    }
    t
};

/// CRC-32 (IEEE) of `data`, continuing from the finished checksum `crc` (0 for an empty prefix).
pub fn crc32_update(crc: u32, data: &[u8]) -> u32 {
    let mut c = !crc;
    for &b in data {
        c = CRC_TABLE[((c ^ u32::from(b)) & 0xff) as usize] ^ (c >> 8);
    }
    !c
}

/// CRC-32 (IEEE) of `data`.
pub fn crc32(data: &[u8]) -> u32 {
    crc32_update(0, data)
}

/// Adler-32 of `data`.
pub fn adler32(data: &[u8]) -> u32 {
    adler32_update(1, data)
}

/// Adler-32 of `data`, continuing from `adler` (1 for an empty prefix). An empty update returns
/// `adler` unchanged.
pub fn adler32_update(adler: u32, data: &[u8]) -> u32 {
    let (mut a, mut b) = (adler & 0xffff, adler >> 16);
    for chunk in data.chunks(5552) {
        for &d in chunk {
            a += u32::from(d);
            b += a;
        }
        a %= 65521;
        b %= 65521;
    }
    b << 16 | a
}

native! {
    /// Borrows the complete byte slice.
    fn msstd_checksum_crc32(data: &[u8]) -> i64 {
        i64::from(crc32(data))
    }
}

#[cfg(test)]
mod tests {
    use super::crc32;

    fn reference(data: &[u8]) -> u32 {
        let mut crc = u32::MAX;
        for &byte in data {
            crc ^= u32::from(byte);
            for _ in 0..8 {
                crc = (crc >> 1) ^ if crc & 1 != 0 { 0xedb8_8320 } else { 0 };
            }
        }
        !crc
    }

    #[test]
    fn ieee_vectors_and_unsigned_high_bit() {
        assert_eq!(crc32(b""), 0);
        assert_eq!(crc32(b"123456789"), 0xcbf4_3926);
        assert_eq!(crc32(b"a"), 0xe8b7_be43);
        assert_eq!(crc32(&[0xff]), 0xff00_0000);
    }

    #[test]
    fn every_length_and_alignment_matches_bit_oracle() {
        let data: alloc::vec::Vec<u8> = (0..1040).map(|i| ((i * 73 + i / 7) % 256) as u8).collect();
        for offset in 0..16 {
            for length in 0..=1024 {
                let view = &data[offset..offset + length];
                assert_eq!(
                    crc32(view),
                    reference(view),
                    "offset {offset}, length {length}"
                );
            }
        }
    }
}

native! {
    /// Resumes the finalized IEEE checksum. Source state is UInt32 and fits Int exactly.
    fn msstd_checksum_crc32_update(initial: i64, data: &[u8]) -> i64 {
        i64::from(crc32_update(initial as u32, data))
    }

    /// Resumes an Adler-32 checksum without retaining or copying any input bytes.
    fn msstd_checksum_adler32_update(initial: i64, data: &[u8]) -> i64 {
        i64::from(adler32_update(initial as u32, data))
    }
}

#[cfg(test)]
mod incremental_tests {
    use super::{adler32_update, crc32, crc32_update};

    fn reference_adler(data: &[u8]) -> u32 {
        let (mut a, mut b) = (1u32, 0u32);
        for &byte in data {
            a = (a + u32::from(byte)) % 65521;
            b = (b + a) % 65521;
        }
        b << 16 | a
    }

    #[test]
    fn adler_vectors_and_empty_states() {
        assert_eq!(adler32_update(1, b""), 1);
        assert_eq!(adler32_update(u32::MAX, b""), u32::MAX);
        assert_eq!(adler32_update(1, b"Wikipedia"), 0x11e6_0398);
        assert_eq!(adler32_update(1, b"123456789"), 0x091e_01de);
        assert_eq!(crc32_update(0, b""), 0);
        assert_eq!(crc32_update(u32::MAX, b""), u32::MAX);
    }

    #[test]
    fn chunks_resume_finalized_checksums() {
        let data: alloc::vec::Vec<u8> = (0..1048576)
            .map(|i| ((i * 73 + i / 7) % 256) as u8)
            .collect();
        for length in [
            0, 1, 7, 16, 31, 32, 255, 256, 5551, 5552, 5553, 65535, 65536, 65537, 1048576,
        ] {
            let input = &data[..length];
            let adler = reference_adler(input);
            assert_eq!(adler32_update(1, input), adler);
            for chunk_size in [1, 3, 16, 255, 4096, 65536] {
                let (mut running_crc, mut running_adler) = (0, 1);
                for chunk in input.chunks(chunk_size) {
                    running_crc = crc32_update(running_crc, chunk);
                    running_adler = adler32_update(running_adler, chunk);
                    assert_eq!(crc32_update(running_crc, b""), running_crc);
                    assert_eq!(adler32_update(running_adler, b""), running_adler);
                }
                assert_eq!(
                    running_crc,
                    crc32(input),
                    "CRC length {length}, chunk {chunk_size}"
                );
                assert_eq!(
                    running_adler, adler,
                    "Adler length {length}, chunk {chunk_size}"
                );
            }
        }
    }
}
