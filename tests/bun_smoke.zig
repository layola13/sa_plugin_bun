const std = @import("std");

extern fn sa_bun_plugin_version(out_ptr: ?*?[*]const u8, out_len: ?*u64) u32;
extern fn sa_bun_plugin_hash_crc32(data: ?[*]const u8, data_len: u64, out_crc: ?*u32) u32;
extern fn sa_bun_plugin_hash_u64(data: ?[*]const u8, data_len: u64, algo: u32, out_hash: ?*u64) u32;
extern fn sa_bun_plugin_gzip_compress(data: ?[*]const u8, data_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32;
extern fn sa_bun_plugin_gzip_decompress(data: ?[*]const u8, data_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32;
extern fn sa_bun_plugin_escape_html(data: ?[*]const u8, data_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32;
extern fn sa_bun_plugin_string_width(data: ?[*]const u8, data_len: u64, out_width: ?*u64) u32;
extern fn sa_bun_plugin_spawn_sync(argv_json: ?[*]const u8, argv_len: u64, cwd: ?[*]const u8, cwd_len: u64, out_code: ?*u32, o_stdout: ?*?[*]const u8, o_stdout_len: ?*u64, o_stderr: ?*?[*]const u8, o_stderr_len: ?*u64) u32;
extern fn sa_bun_plugin_hash_wyhash64(data: ?[*]const u8, data_len: u64, seed: u64, out_hash: ?*u64) u32;
extern fn sa_bun_plugin_hash_xxhash64(data: ?[*]const u8, data_len: u64, seed: u64, out_hash: ?*u64) u32;
extern fn sa_bun_plugin_hash_xxhash32(data: ?[*]const u8, data_len: u64, seed: u32, out_hash: ?*u32) u32;
extern fn sa_bun_plugin_hash_adler32(data: ?[*]const u8, data_len: u64, out_hash: ?*u32) u32;
extern fn sa_bun_plugin_hasher_new(algo: u32, out_handle: ?*?*anyopaque) u32;
extern fn sa_bun_plugin_hasher_update(handle: ?*anyopaque, data: ?[*]const u8, data_len: u64) u32;
extern fn sa_bun_plugin_hasher_digest_hex(handle: ?*anyopaque, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32;
extern fn sa_bun_plugin_hasher_free(handle: ?*anyopaque) u32;
extern fn sa_bun_plugin_hmac_sha256_hex(key: ?[*]const u8, key_len: u64, data: ?[*]const u8, data_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32;
extern fn sa_bun_plugin_s3_sigv4_signature(secret: ?[*]const u8, secret_len: u64, date: ?[*]const u8, date_len: u64, region: ?[*]const u8, region_len: u64, service: ?[*]const u8, service_len: u64, sts: ?[*]const u8, sts_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32;
extern fn sa_bun_plugin_semver_cmp(a: ?[*]const u8, a_len: u64, b: ?[*]const u8, b_len: u64, out_order: ?*i32) u32;
extern fn sa_bun_plugin_shell_exec(cmd: ?[*]const u8, cmd_len: u64, cwd: ?[*]const u8, cwd_len: u64, out_code: ?*u32, o_stdout: ?*?[*]const u8, o_stdout_len: ?*u64, o_stderr: ?*?[*]const u8, o_stderr_len: ?*u64) u32;

pub fn main() !void {
    var ok = true;
    const check = struct {
        fn c(okp: *bool, name: []const u8, cond: bool) void {
            if (!cond) {
                std.debug.print("FAIL {s}\n", .{name});
                okp.* = false;
            } else {
                std.debug.print("ok {s}\n", .{name});
            }
        }
    }.c;

    var vptr: ?[*]const u8 = null;
    var vlen: u64 = 0;
    check(&ok, "version-status", sa_bun_plugin_version(&vptr, &vlen) == 0);
    check(&ok, "version-value", std.mem.eql(u8, vptr.?[0..vlen], "1.4.2"));

    var crc: u32 = 0;
    const digits = "123456789";
    check(&ok, "crc32-status", sa_bun_plugin_hash_crc32(digits.ptr, digits.len, &crc) == 0);
    check(&ok, "crc32-value", crc == 0xCBF43926);

    var h: u64 = 0;
    const empty = "";
    const eptr: ?[*]const u8 = if (empty.len == 0) @ptrFromInt(0x1000) else empty.ptr;
    check(&ok, "fnv-status", sa_bun_plugin_hash_u64(eptr, 0, 0, &h) == 0);
    check(&ok, "fnv-empty-is-offset-basis", h == 0xcbf29ce484222325);

    const raw = "hello bun std smoke test 1234567890!@#";
    var cptr: ?[*]const u8 = null;
    var clen: u64 = 0;
    check(&ok, "gzip-status", sa_bun_plugin_gzip_compress(raw.ptr, raw.len, &cptr, &clen) == 0);
    var dptr: ?[*]const u8 = null;
    var dlen: u64 = 0;
    check(&ok, "gunzip-status", sa_bun_plugin_gzip_decompress(cptr, clen, &dptr, &dlen) == 0);
    check(&ok, "gzip-roundtrip", std.mem.eql(u8, dptr.?[0..dlen], raw));

    const html = "<a href=\"x\">&'</a>";
    var hptr: ?[*]const u8 = null;
    var hlen: u64 = 0;
    check(&ok, "escape-status", sa_bun_plugin_escape_html(html.ptr, html.len, &hptr, &hlen) == 0);
    check(&ok, "escape-value", std.mem.eql(u8, hptr.?[0..hlen], "&lt;a href=&quot;x&quot;&gt;&amp;&#x27;&lt;/a&gt;"));

    const mixed = "hi\xe4\xb8\xad";
    var w: u64 = 0;
    check(&ok, "width-status", sa_bun_plugin_string_width(mixed.ptr, mixed.len, &w) == 0);
    check(&ok, "width-value", w == 4);

    const argv = "[\"/bin/echo\",\"hi\"]";
    var code: u32 = 99;
    var so: ?[*]const u8 = null;
    var sol: u64 = 0;
    var se: ?[*]const u8 = null;
    var sel: u64 = 0;
    check(&ok, "spawn-status", sa_bun_plugin_spawn_sync(argv.ptr, argv.len, null, 0, &code, &so, &sol, &se, &sel) == 0);
    check(&ok, "spawn-code", code == 0);
    check(&ok, "spawn-stdout", std.mem.eql(u8, so.?[0..sol], "hi\n"));

    // --- round 2: bit-exact hashes vs upstream vectors + live bun 1.4.2 ---
    const hw = "hello world";
    var wy: u64 = 0;
    check(&ok, "wyhash-status", sa_bun_plugin_hash_wyhash64(hw.ptr, hw.len, 0, &wy) == 0);
    check(&ok, "wyhash-hello", wy == 0x668d5e431c3b2573);
    var xx: u64 = 0;
    check(&ok, "xxh64-status", sa_bun_plugin_hash_xxhash64(hw.ptr, hw.len, 0, &xx) == 0);
    check(&ok, "xxh64-hello", xx == 0x45ab6734b21e6968);
    const big_seed: u64 = 16269921104521594740;
    var xxs: u64 = 0;
    check(&ok, "xxh64-seed", sa_bun_plugin_hash_xxhash64(empty.ptr, empty.len, big_seed, &xxs) == 0 and xxs == 3224619365169652240);
    var x32: u32 = 0;
    check(&ok, "xxh32-hello", sa_bun_plugin_hash_xxhash32(hw.ptr, hw.len, 0, &x32) == 0 and x32 == 0xcebb6622);
    var ad: u32 = 0;
    check(&ok, "adler-hello", sa_bun_plugin_hash_adler32(hw.ptr, hw.len, &ad) == 0 and ad == 0x1a0b045d);
    // hash_u64 dispatch now wired to the real algorithms (seed 0)
    var du: u64 = 0;
    check(&ok, "dispatch-wyhash", sa_bun_plugin_hash_u64(hw.ptr, hw.len, 2, &du) == 0 and du == 0x668d5e431c3b2573);
    check(&ok, "dispatch-xxhash", sa_bun_plugin_hash_u64(hw.ptr, hw.len, 3, &du) == 0 and du == 0x45ab6734b21e6968);
    // long inputs crossing 48-byte rounds / final paths (live bun 1.4.2 values)
    var mk: [240]u8 = undefined;
    for (&mk, 0..) |*b, i| b.* = @as(u8, @truncate((i * 191 + 17) & 0xff));
    var wy240: u64 = 0;
    check(&ok, "wyhash-240", sa_bun_plugin_hash_wyhash64(&mk, 240, 0, &wy240) == 0 and wy240 == 0x8cc2a3578f2e5360);
    var xx240: u64 = 0;
    check(&ok, "xxh64-240", sa_bun_plugin_hash_xxhash64(&mk, 240, 0, &xx240) == 0 and xx240 == 0xb1d89115ab8aa560);
    var wyseed: u64 = 0;
    check(&ok, "wyhash-seed42", sa_bun_plugin_hash_wyhash64(hw.ptr, hw.len, 42, &wyseed) == 0 and wyseed == 0xe8ab5bdd73612b2);
    // reference makeInput vectors from test/js/bun/util/hash.test.js
    var x32s: u32 = 0;
    check(&ok, "xxh32-16-seed", sa_bun_plugin_hash_xxhash32(mk[0..16].ptr, 16, 0xabcdef01, &x32s) == 0 and x32s == 0x850a7a8c);
    var xx0: u64 = 0;
    check(&ok, "xxh64-empty", sa_bun_plugin_hash_xxhash64(eptr, 0, 0, &xx0) == 0 and xx0 == 0xef46db3751d8e999);

    // --- CryptoHasher: sha256("abc") well-known digest, incremental update ---
    var hdl: ?*anyopaque = null;
    check(&ok, "hasher-new", sa_bun_plugin_hasher_new(0, &hdl) == 0);
    const abc = "abc";
    check(&ok, "hasher-update", sa_bun_plugin_hasher_update(hdl, abc.ptr, 2) == 0 and sa_bun_plugin_hasher_update(hdl, abc[2..].ptr, 1) == 0);
    var dg: ?[*]const u8 = null;
    var dgl: u64 = 0;
    check(&ok, "hasher-digest", sa_bun_plugin_hasher_digest_hex(hdl, &dg, &dgl) == 0 and std.mem.eql(u8, dg.?[0..dgl], "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"));
    check(&ok, "hasher-free", sa_bun_plugin_hasher_free(hdl) == 0);

    // --- HMAC-SHA256 (RFC 4231 TC1, dual oracle: CPython + OpenSSL) ---
    var kb: [20]u8 = undefined;
    @memset(&kb, 0x0b);
    const hi = "Hi There";
    var hm: ?[*]const u8 = null;
    var hml: u64 = 0;
    check(&ok, "hmac-tc1", sa_bun_plugin_hmac_sha256_hex(&kb, 20, hi.ptr, hi.len, &hm, &hml) == 0 and std.mem.eql(u8, hm.?[0..hml], "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"));

    // --- SigV4 (oracle: CPython hmac chain) ---
    const sec = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY";
    const dt = "20150830";
    const rg = "us-east-1";
    const sv = "iam";
    const sts = "test-string-to-sign";
    var sg: ?[*]const u8 = null;
    var sgl: u64 = 0;
    check(&ok, "sigv4", sa_bun_plugin_s3_sigv4_signature(sec.ptr, sec.len, dt.ptr, dt.len, rg.ptr, rg.len, sv.ptr, sv.len, sts.ptr, sts.len, &sg, &sgl) == 0 and std.mem.eql(u8, sg.?[0..sgl], "affe64210ef3f6c6d0556a3ea1e5bde440eab337ad99ff915e3c723327ecae32"));

    // --- semver ---
    var ord: i32 = 99;
    const v123 = "1.2.3";
    const v1100 = "1.10.0";
    check(&ok, "semver-lt", sa_bun_plugin_semver_cmp(v123.ptr, v123.len, v1100.ptr, v1100.len, &ord) == 0 and ord == -1);
    const v200a = "2.0.0-alpha";
    const v200 = "2.0.0";
    check(&ok, "semver-pre", sa_bun_plugin_semver_cmp(v200a.ptr, v200a.len, v200.ptr, v200.len, &ord) == 0 and ord == -1);
    check(&ok, "semver-eq", sa_bun_plugin_semver_cmp(v200.ptr, v200.len, v200.ptr, v200.len, &ord) == 0 and ord == 0);

    // --- shell_exec ($ sync subset) ---
    const sh = "echo hi";
    var sc: u32 = 99;
    var sso: ?[*]const u8 = null;
    var ssol: u64 = 0;
    var sse: ?[*]const u8 = null;
    var ssel: u64 = 0;
    check(&ok, "shexec", sa_bun_plugin_shell_exec(sh.ptr, sh.len, null, 0, &sc, &sso, &ssol, &sse, &ssel) == 0 and sc == 0 and std.mem.eql(u8, sso.?[0..ssol], "hi\n"));

    if (!ok) std.process.exit(1);
    std.debug.print("ALL SMOKE OK\n", .{});
}
