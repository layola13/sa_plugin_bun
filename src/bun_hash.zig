const std = @import("std");

// Bit-exact ports of the upstream hashers used by `Bun.hash`.
// Sources (shallow clone /tmp/opencode/bun @ 9f70da07):
//   - wyhash final4 one-shot: src/wyhash/lib.rs (`Wyhash::hash`, "used by bun.hash()").
//     Pinned by test/js/bun/util/hash.test.js: Bun.hash("hello world") = 0x668d5e431c3b2573.
//   - XXH64/XXH32: src/hash/xxhash.rs via src/highway ("Bit-identical to the xxHash
//     reference"); pinned by the "xxHash32 / xxHash64 reference vectors" suite.
//   - Adler32: src/hash/adler32.rs (zlib-compatible).

fn readU32LE(data: []const u8) u32 {
    return std.mem.readInt(u32, data[0..4], .little);
}

fn readU64LE(data: []const u8) u64 {
    return std.mem.readInt(u64, data[0..8], .little);
}

// ── wyhash final4 ──────────────────────────────────────────────
const WY_S = [4]u64{
    0xa0761d6478bd642f,
    0xe7037ed1a0b428db,
    0x8ebc6af09c88c6e3,
    0x589965cc75374cc3,
};

fn wyMix(a: u64, b: u64) u64 {
    const x: u128 = @as(u128, a) * @as(u128, b);
    return @as(u64, @truncate(x)) ^ @as(u64, @truncate(x >> 64));
}

pub fn wyhashFinal4(seed: u64, input: []const u8) u64 {
    const s0 = seed ^ wyMix(seed ^ WY_S[0], WY_S[1]);
    var state = [3]u64{ s0, s0, s0 };
    var a: u64 = 0;
    var b: u64 = 0;

    if (input.len <= 16) {
        if (input.len >= 4) {
            const end = input.len - 4;
            const quarter = (input.len >> 3) << 2;
            a = (@as(u64, readU32LE(input[0..4])) << 32) | @as(u64, readU32LE(input[quarter .. quarter + 4]));
            b = (@as(u64, readU32LE(input[end .. end + 4])) << 32) | @as(u64, readU32LE(input[end - quarter .. end - quarter + 4]));
        } else if (input.len != 0) {
            a = (@as(u64, input[0]) << 16) | (@as(u64, input[input.len >> 1]) << 8) | @as(u64, input[input.len - 1]);
            b = 0;
        } else {
            a = 0;
            b = 0;
        }
    } else {
        var i: usize = 0;
        if (input.len >= 48) {
            const bound = input.len - 48;
            while (i < bound) : (i += 48) {
                const m0: u128 = @as(u128, readU64LE(input[i..]) ^ WY_S[1]) * @as(u128, readU64LE(input[i + 8 ..]) ^ state[0]);
                state[0] = @as(u64, @truncate(m0)) ^ @as(u64, @truncate(m0 >> 64));
                const m1: u128 = @as(u128, readU64LE(input[i + 16 ..]) ^ WY_S[2]) * @as(u128, readU64LE(input[i + 24 ..]) ^ state[1]);
                state[1] = @as(u64, @truncate(m1)) ^ @as(u64, @truncate(m1 >> 64));
                const m2: u128 = @as(u128, readU64LE(input[i + 32 ..]) ^ WY_S[3]) * @as(u128, readU64LE(input[i + 40 ..]) ^ state[2]);
                state[2] = @as(u64, @truncate(m2)) ^ @as(u64, @truncate(m2 >> 64));
            }
            state[0] ^= state[1] ^ state[2]; // final0
        }
        // final1(input, i)
        const tail = input[i..];
        var j: usize = 0;
        while (j + 16 < tail.len) : (j += 16) {
            state[0] = wyMix(readU64LE(tail[j..]) ^ WY_S[1], readU64LE(tail[j + 8 ..]) ^ state[0]);
        }
        a = readU64LE(input[input.len - 16 ..]);
        b = readU64LE(input[input.len - 8 ..]);
    }

    // final2
    a ^= WY_S[1];
    b ^= state[0];
    const x: u128 = @as(u128, a) * @as(u128, b);
    a = @as(u64, @truncate(x));
    b = @as(u64, @truncate(x >> 64));
    return wyMix(a ^ WY_S[0] ^ @as(u64, input.len), b ^ WY_S[1]);
}

// ── XXH64 (reference) ──────────────────────────────────────────
const XXH64_P1: u64 = 0x9E3779B185EBCA87;
const XXH64_P2: u64 = 0xC2B2AE3D27D4EB4F;
const XXH64_P3: u64 = 0x165667B19E3779F9;
const XXH64_P4: u64 = 0x85EBCA77C2B2AE63;
const XXH64_P5: u64 = 0x27D4EB2F165667C5;

fn xxh64Round(acc: u64, input: u64) u64 {
    var a = acc +% input *% XXH64_P2;
    a = std.math.rotl(u64, a, 31);
    return a *% XXH64_P1;
}

fn xxh64Merge(acc: u64, val: u64) u64 {
    var v = xxh64Round(0, val);
    v = acc ^ v;
    return v *% XXH64_P1 +% XXH64_P4;
}

pub fn xxhash64(seed: u64, input: []const u8) u64 {
    var h: u64 = 0;
    var i: usize = 0;
    if (input.len >= 32) {
        var v1 = seed +% XXH64_P1 +% XXH64_P2;
        var v2 = seed +% XXH64_P2;
        var v3 = seed;
        var v4 = seed -% XXH64_P1;
        while (i + 32 <= input.len) : (i += 32) {
            v1 = xxh64Round(v1, readU64LE(input[i..]));
            v2 = xxh64Round(v2, readU64LE(input[i + 8 ..]));
            v3 = xxh64Round(v3, readU64LE(input[i + 16 ..]));
            v4 = xxh64Round(v4, readU64LE(input[i + 24 ..]));
        }
        h = std.math.rotl(u64, v1, 1) +% std.math.rotl(u64, v2, 7) +% std.math.rotl(u64, v3, 12) +% std.math.rotl(u64, v4, 18);
        h = xxh64Merge(h, v1);
        h = xxh64Merge(h, v2);
        h = xxh64Merge(h, v3);
        h = xxh64Merge(h, v4);
    } else {
        h = seed +% XXH64_P5;
    }
    h +%= input.len;
    while (i + 8 <= input.len) : (i += 8) {
        const k1 = xxh64Round(0, readU64LE(input[i..]));
        h ^= k1;
        h = std.math.rotl(u64, h, 27) *% XXH64_P1 +% XXH64_P4;
    }
    if (i + 4 <= input.len) {
        h ^= @as(u64, readU32LE(input[i..])) *% XXH64_P1;
        h = std.math.rotl(u64, h, 23) *% XXH64_P2 +% XXH64_P3;
        i += 4;
    }
    while (i < input.len) : (i += 1) {
        h ^= @as(u64, input[i]) *% XXH64_P5;
        h = std.math.rotl(u64, h, 11) *% XXH64_P1;
    }
    h ^= h >> 33;
    h *%= XXH64_P2;
    h ^= h >> 29;
    h *%= XXH64_P3;
    h ^= h >> 32;
    return h;
}

// ── XXH32 (reference) ──────────────────────────────────────────
const XXH32_P1: u32 = 0x9E3779B1;
const XXH32_P2: u32 = 0x85EBCA77;
const XXH32_P3: u32 = 0xC2B2AE3D;
const XXH32_P4: u32 = 0x27D4EB2F;
const XXH32_P5: u32 = 0x165667B1;

fn xxh32Round(acc: u32, input: u32) u32 {
    var a = acc +% input *% XXH32_P2;
    a = std.math.rotl(u32, a, 13);
    return a *% XXH32_P1;
}

pub fn xxhash32(seed: u32, input: []const u8) u32 {
    var h: u32 = undefined;
    var i: usize = 0;
    if (input.len >= 16) {
        var v1 = seed +% XXH32_P1 +% XXH32_P2;
        var v2 = seed +% XXH32_P2;
        var v3 = seed;
        var v4 = seed -% XXH32_P1;
        while (i + 16 <= input.len) : (i += 16) {
            v1 = xxh32Round(v1, readU32LE(input[i..]));
            v2 = xxh32Round(v2, readU32LE(input[i + 4 ..]));
            v3 = xxh32Round(v3, readU32LE(input[i + 8 ..]));
            v4 = xxh32Round(v4, readU32LE(input[i + 12 ..]));
        }
        h = std.math.rotl(u32, v1, 1) +% std.math.rotl(u32, v2, 7) +% std.math.rotl(u32, v3, 12) +% std.math.rotl(u32, v4, 18);
    } else {
        h = seed +% XXH32_P5;
    }
    h +%= @as(u32, @intCast(input.len));
    while (i + 4 <= input.len) : (i += 4) {
        h +%= readU32LE(input[i..]) *% XXH32_P3;
        h = std.math.rotl(u32, h, 17) *% XXH32_P4;
    }
    while (i < input.len) : (i += 1) {
        h +%= @as(u32, input[i]) *% XXH32_P5;
        h = std.math.rotl(u32, h, 11) *% XXH32_P1;
    }
    h ^= h >> 15;
    h *%= XXH32_P2;
    h ^= h >> 13;
    h *%= XXH32_P3;
    h ^= h >> 16;
    return h;
}

// ── Adler32 (zlib-compatible) ──────────────────────────────────
pub fn adler32(input: []const u8) u32 {
    const MOD: u32 = 65521;
    var a: u32 = 1;
    var b: u32 = 0;
    var i: usize = 0;
    // NMAX blocking to keep a/b in range without per-byte modulo.
    while (i < input.len) {
        const chunk = @min(input.len - i, 5552);
        const end = i + chunk;
        while (i < end) : (i += 1) {
            a += input[i];
            b += a;
        }
        a %= MOD;
        b %= MOD;
    }
    return (b << 16) | a;
}
