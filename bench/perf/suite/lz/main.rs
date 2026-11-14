fn lcg(x: i64) -> i64 { (x * 1103515245 + 12345) % 2147483648 }

fn make_input(n: usize) -> Vec<i64> {
    let mut vocab: Vec<Vec<i64>> = Vec::new();
    let mut x = 17;
    for _ in 0..200 {
        let mut word = Vec::new();
        x = lcg(x);
        for _ in 0..(3 + x / 11 % 8) {
            x = lcg(x);
            word.push(97 + x / 13 % 26);
        }
        vocab.push(word);
    }
    let mut out = Vec::new();
    while out.len() < n {
        x = lcg(x);
        out.extend_from_slice(&vocab[(x / 17 % 200) as usize]);
        out.push(32);
    }
    out
}

fn compress(data: &[i64]) -> Vec<i64> {
    let mut head = vec![-1i64; 65536];
    let mut out = Vec::new();
    let n = data.len();
    let mut i = 0;
    while i < n {
        let (mut best, mut dist) = (0usize, 0usize);
        if i + 3 <= n {
            let h = ((data[i] * 506832829 + data[i + 1] * 65599 + data[i + 2]) % 65536) as usize;
            let cand = head[h];
            head[h] = i as i64;
            if cand >= 0 && i - (cand as usize) < 32768 {
                let cand = cand as usize;
                let mut len = 0;
                while i + len < n && len < 255 && data[cand + len] == data[i + len] { len += 1; }
                if len >= 3 { best = len; dist = i - cand; }
            }
        }
        if best >= 3 {
            out.push(256 + best as i64);
            out.push(dist as i64);
            i += best;
        } else {
            out.push(data[i]);
            i += 1;
        }
    }
    out
}

fn decompress(tokens: &[i64]) -> Vec<i64> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < tokens.len() {
        let t = tokens[i];
        if t < 256 {
            out.push(t);
            i += 1;
        } else {
            let len = (t - 256) as usize;
            let start = out.len() - tokens[i + 1] as usize;
            for k in 0..len { let v = out[start + k]; out.push(v); }
            i += 2;
        }
    }
    out
}

fn main() {
    let data = make_input(4000000);
    let mut checksum = 0;
    for _ in 0..3 {
        let packed = compress(&data);
        let unpacked = decompress(&packed);
        if unpacked != data { println!("MISMATCH"); }
        checksum += packed.len();
    }
    println!("input {} tokens {}", data.len(), checksum);
}
