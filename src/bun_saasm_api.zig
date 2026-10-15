const std = @import("std");
const builtin = @import("builtin");
const bun_hash = @import("bun_hash.zig");

// Bun compatibility plugin: native SA replacement surface for the
// synchronous, deterministic subset of the Bun namespace.
// Upstream source of truth (shallow clone):
//   /tmp/opencode/bun/packages/bun-types/bun.d.ts (v1.4.2, HEAD 9f70da07)
// It does not call the `bun` executable and does not embed the Bun runtime.
//
// Status convention: 0 = ok, 1 = not-found/null, 2 = error, 3 = unsupported-stub.

// --- POSIX/C signatures ---
extern fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern fn unsetenv(name: [*:0]const u8) c_int;
extern fn getenv(name: [*:0]const u8) ?[*:0]u8;

const BUN_VERSION = "1.4.2";
const BUN_REVISION = "9f70da07";

fn writeOwned(out_ptr: ?*?[*]const u8, out_len: ?*u64, bytes: []const u8) u32 {
    const owned = std.heap.page_allocator.dupe(u8, bytes) catch return 2;
    const ptr_slot = out_ptr orelse {
        std.heap.page_allocator.free(owned);
        return 2;
    };
    const len_slot = out_len orelse {
        std.heap.page_allocator.free(owned);
        return 2;
    };
    ptr_slot.* = owned.ptr;
    len_slot.* = owned.len;
    return 0;
}

fn openFilePath(path: []const u8, flags: std.fs.File.OpenFlags) !std.fs.File {
    if (std.fs.path.isAbsolute(path)) {
        return std.fs.openFileAbsolute(path, flags);
    }
    return std.fs.cwd().openFile(path, flags);
}

fn createFilePath(path: []const u8, flags: std.fs.File.CreateFlags) !std.fs.File {
    if (std.fs.path.isAbsolute(path)) {
        return std.fs.createFileAbsolute(path, flags);
    }
    return std.fs.cwd().createFile(path, flags);
}

// --- free buffer ---
pub export fn sa_bun_plugin_free_buffer(ptr: ?[*]const u8, len: u64) u32 {
    if (ptr) |p| {
        const slice = p[0..len];
        std.heap.page_allocator.free(slice);
    }
    return 0;
}

// --- runtime info ---
pub export fn sa_bun_plugin_version(out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    return writeOwned(out_ptr, out_len, BUN_VERSION);
}

pub export fn sa_bun_plugin_revision(out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    return writeOwned(out_ptr, out_len, BUN_REVISION);
}

pub export fn sa_bun_plugin_main(out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    const exe = std.fs.selfExePathAlloc(std.heap.page_allocator) catch return 2;
    defer std.heap.page_allocator.free(exe);
    return writeOwned(out_ptr, out_len, exe);
}

pub export fn sa_bun_plugin_argv_json(out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    const args = std.process.argsAlloc(std.heap.page_allocator) catch return 2;
    defer std.process.argsFree(std.heap.page_allocator, args);
    // Full argv including argv[0], matching Bun.argv ([bun, script, ...args]).
    const json = std.json.stringifyAlloc(std.heap.page_allocator, args, .{}) catch return 2;
    const ptr_slot = out_ptr orelse {
        std.heap.page_allocator.free(json);
        return 2;
    };
    const len_slot = out_len orelse {
        std.heap.page_allocator.free(json);
        return 2;
    };
    ptr_slot.* = json.ptr;
    len_slot.* = json.len;
    return 0;
}

pub export fn sa_bun_plugin_cwd(out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.process.getCwd(&buf) catch return 2;
    return writeOwned(out_ptr, out_len, path);
}

pub export fn sa_bun_plugin_which(cmd_ptr: ?[*]const u8, cmd_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    if (cmd_ptr == null or cmd_len == 0) return 2;
    const cmd = cmd_ptr.?[0..cmd_len];
    if (std.mem.indexOfScalar(u8, cmd, '/') != null) {
        const z = std.heap.page_allocator.dupeZ(u8, cmd) catch return 2;
        defer std.heap.page_allocator.free(z);
        std.posix.access(z, std.posix.X_OK) catch return 1;
        return writeOwned(out_ptr, out_len, cmd);
    }
    const path_z = getenv("PATH") orelse return 1;
    const path = std.mem.span(path_z);
    var it = std.mem.splitScalar(u8, path, ':');
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        const full = std.fmt.bufPrint(&buf, "{s}/{s}", .{ dir, cmd }) catch continue;
        const z = std.heap.page_allocator.dupeZ(u8, full) catch return 2;
        defer std.heap.page_allocator.free(z);
        std.posix.access(z, std.posix.X_OK) catch continue;
        return writeOwned(out_ptr, out_len, full);
    }
    return 1;
}

// --- path helpers ---
fn hexVal(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return null;
}

pub export fn sa_bun_plugin_file_url_to_path(url_ptr: ?[*]const u8, url_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    if (url_ptr == null or url_len == 0) return 2;
    const url = url_ptr.?[0..url_len];
    const prefix = "file://";
    const rest = if (std.mem.startsWith(u8, url, prefix)) url[prefix.len..] else url;
    var list = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer list.deinit();
    var i: usize = 0;
    while (i < rest.len) {
        if (rest[i] == '%' and i + 2 < rest.len) {
            const hi = hexVal(rest[i + 1]) orelse {
                list.append(rest[i]) catch return 2;
                i += 1;
                continue;
            };
            const lo = hexVal(rest[i + 2]) orelse {
                list.append(rest[i]) catch return 2;
                i += 1;
                continue;
            };
            list.append(hi * 16 + lo) catch return 2;
            i += 3;
        } else {
            list.append(rest[i]) catch return 2;
            i += 1;
        }
    }
    const slice = list.toOwnedSlice() catch return 2;
    defer std.heap.page_allocator.free(slice);
    return writeOwned(out_ptr, out_len, slice);
}

pub export fn sa_bun_plugin_path_to_file_url(path_ptr: ?[*]const u8, path_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    if (path_ptr == null or path_len == 0) return 2;
    const path = path_ptr.?[0..path_len];
    var list = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer list.deinit();
    list.appendSlice("file://") catch return 2;
    if (!std.fs.path.isAbsolute(path)) {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const cwd = std.process.getCwd(&buf) catch return 2;
        list.appendSlice(cwd) catch return 2;
        list.append('/') catch return 2;
    }
    list.appendSlice(path) catch return 2;
    const slice = list.toOwnedSlice() catch return 2;
    defer std.heap.page_allocator.free(slice);
    return writeOwned(out_ptr, out_len, slice);
}

// --- time ---
pub export fn sa_bun_plugin_nanoseconds(out_ns: ?*u64) u32 {
    const slot = out_ns orelse return 2;
    const ns = std.time.nanoTimestamp();
    slot.* = @intCast(@max(ns, 0));
    return 0;
}

pub export fn sa_bun_plugin_sleep_sync(ms: u64) u32 {
    const ns = std.math.mul(u64, ms, 1_000_000) catch return 2;
    std.Thread.sleep(ns);
    return 0;
}

// --- env (Bun.env parity) ---
pub export fn sa_bun_plugin_env_get(key_ptr: ?[*]const u8, key_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    if (key_ptr == null or key_len == 0) return 2;
    const key = key_ptr.?[0..key_len];
    const key_z = std.heap.page_allocator.dupeZ(u8, key) catch return 2;
    defer std.heap.page_allocator.free(key_z);
    const value = getenv(key_z.ptr) orelse return 1;
    return writeOwned(out_ptr, out_len, std.mem.span(value));
}

pub export fn sa_bun_plugin_env_set(key_ptr: ?[*]const u8, key_len: u64, val_ptr: ?[*]const u8, val_len: u64) u32 {
    if (key_ptr == null or key_len == 0 or val_ptr == null) return 2;
    const key = key_ptr.?[0..key_len];
    const val = val_ptr.?[0..val_len];
    const key_z = std.heap.page_allocator.dupeZ(u8, key) catch return 2;
    defer std.heap.page_allocator.free(key_z);
    const val_z = std.heap.page_allocator.dupeZ(u8, val) catch return 2;
    defer std.heap.page_allocator.free(val_z);
    if (setenv(key_z.ptr, val_z.ptr, 1) != 0) return 2;
    return 0;
}

pub export fn sa_bun_plugin_env_delete(key_ptr: ?[*]const u8, key_len: u64) u32 {
    if (key_ptr == null or key_len == 0) return 2;
    const key = key_ptr.?[0..key_len];
    const key_z = std.heap.page_allocator.dupeZ(u8, key) catch return 2;
    defer std.heap.page_allocator.free(key_z);
    if (unsetenv(key_z.ptr) != 0) return 2;
    return 0;
}

// --- file: Bun.file().text/bytes + Bun.write ---
pub export fn sa_bun_plugin_file_read_text(path_ptr: ?[*]const u8, path_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    if (path_ptr == null or path_len == 0) return 2;
    const path = path_ptr.?[0..path_len];
    var file = openFilePath(path, .{}) catch return 2;
    defer file.close();
    const stat = file.stat() catch return 2;
    if (stat.size > 64 * 1024 * 1024) return 2;
    const content = file.readToEndAlloc(std.heap.page_allocator, 64 * 1024 * 1024) catch return 2;
    errdefer std.heap.page_allocator.free(content);
    if (!std.unicode.utf8ValidateSlice(content)) {
        std.heap.page_allocator.free(content);
        return 2;
    }
    const ptr_slot = out_ptr orelse {
        std.heap.page_allocator.free(content);
        return 2;
    };
    const len_slot = out_len orelse {
        std.heap.page_allocator.free(content);
        return 2;
    };
    ptr_slot.* = content.ptr;
    len_slot.* = content.len;
    return 0;
}

pub export fn sa_bun_plugin_file_read_base64(path_ptr: ?[*]const u8, path_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    if (path_ptr == null or path_len == 0) return 2;
    const path = path_ptr.?[0..path_len];
    var file = openFilePath(path, .{}) catch return 2;
    defer file.close();
    const content = file.readToEndAlloc(std.heap.page_allocator, 64 * 1024 * 1024) catch return 2;
    defer std.heap.page_allocator.free(content);
    const encoded_len = std.base64.standard.Encoder.calcSize(content.len);
    const encoded = std.heap.page_allocator.alloc(u8, encoded_len) catch return 2;
    errdefer std.heap.page_allocator.free(encoded);
    _ = std.base64.standard.Encoder.encode(encoded, content);
    const ptr_slot = out_ptr orelse {
        std.heap.page_allocator.free(encoded);
        return 2;
    };
    const len_slot = out_len orelse {
        std.heap.page_allocator.free(encoded);
        return 2;
    };
    ptr_slot.* = encoded.ptr;
    len_slot.* = encoded.len;
    return 0;
}

pub export fn sa_bun_plugin_write_text_file(path_ptr: ?[*]const u8, path_len: u64, data_ptr: ?[*]const u8, data_len: u64) u32 {
    if (path_ptr == null or path_len == 0 or data_ptr == null) return 2;
    const path = path_ptr.?[0..path_len];
    const data = data_ptr.?[0..data_len];
    var file = createFilePath(path, .{}) catch return 2;
    defer file.close();
    file.writeAll(data) catch return 2;
    return 0;
}

pub export fn sa_bun_plugin_write_file_base64(path_ptr: ?[*]const u8, path_len: u64, base64_ptr: ?[*]const u8, base64_len: u64) u32 {
    if (path_ptr == null or path_len == 0 or base64_ptr == null or base64_len == 0) return 2;
    const path = path_ptr.?[0..path_len];
    const enc = base64_ptr.?[0..base64_len];
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(enc) catch return 2;
    const decoded = std.heap.page_allocator.alloc(u8, decoded_len) catch return 2;
    defer std.heap.page_allocator.free(decoded);
    std.base64.standard.Decoder.decode(decoded, enc) catch return 2;
    var file = createFilePath(path, .{}) catch return 2;
    defer file.close();
    file.writeAll(decoded) catch return 2;
    return 0;
}

pub export fn sa_bun_plugin_file_size(path_ptr: ?[*]const u8, path_len: u64, out_size: ?*u64) u32 {
    if (path_ptr == null or path_len == 0) return 2;
    const slot = out_size orelse return 2;
    const path = path_ptr.?[0..path_len];
    var file = openFilePath(path, .{}) catch return 2;
    defer file.close();
    const stat = file.stat() catch return 2;
    slot.* = stat.size;
    return 0;
}

pub export fn sa_bun_plugin_file_exists(path_ptr: ?[*]const u8, path_len: u64, out_bool: ?*u8) u32 {
    if (path_ptr == null or path_len == 0) return 2;
    const slot = out_bool orelse return 2;
    const path = path_ptr.?[0..path_len];
    if (std.fs.path.isAbsolute(path)) {
        std.fs.accessAbsolute(path, .{}) catch {
            slot.* = 0;
            return 0;
        };
    } else {
        std.fs.cwd().access(path, .{}) catch {
            slot.* = 0;
            return 0;
        };
    }
    slot.* = 1;
    return 0;
}

pub export fn sa_bun_plugin_mkdir(path_ptr: ?[*]const u8, path_len: u64, recursive: u8) u32 {
    if (path_ptr == null or path_len == 0) return 2;
    const path = path_ptr.?[0..path_len];
    if (recursive == 0) {
        if (std.fs.path.isAbsolute(path)) {
            std.fs.makeDirAbsolute(path) catch return 2;
        } else {
            std.fs.cwd().makeDir(path) catch return 2;
        }
    } else {
        if (std.fs.path.isAbsolute(path)) {
            std.fs.makeDirAbsolute(path) catch |err| {
                if (err != error.PathAlreadyExists) return 2;
            };
            // best-effort parents for absolute paths
            var tmp = std.heap.page_allocator.dupe(u8, path) catch return 2;
            defer std.heap.page_allocator.free(tmp);
            var i: usize = 1;
            while (i < tmp.len) : (i += 1) {
                if (tmp[i] == '/') {
                    tmp[i] = 0;
                    const part = tmp[0..i];
                    std.fs.makeDirAbsolute(part) catch {};
                    tmp[i] = '/';
                }
            }
            std.fs.makeDirAbsolute(path) catch |err| {
                if (err != error.PathAlreadyExists) return 2;
            };
        } else {
            std.fs.cwd().makePath(path) catch return 2;
        }
    }
    return 0;
}

pub export fn sa_bun_plugin_remove(path_ptr: ?[*]const u8, path_len: u64, recursive: u8) u32 {
    if (path_ptr == null or path_len == 0) return 2;
    const path = path_ptr.?[0..path_len];
    if (recursive == 0) {
        if (std.fs.path.isAbsolute(path)) {
            std.fs.deleteFileAbsolute(path) catch {
                std.fs.deleteDirAbsolute(path) catch return 2;
            };
        } else {
            std.fs.cwd().deleteFile(path) catch {
                std.fs.cwd().deleteDir(path) catch return 2;
            };
        }
    } else {
        if (std.fs.path.isAbsolute(path)) {
            std.fs.deleteTreeAbsolute(path) catch return 2;
        } else {
            std.fs.cwd().deleteTree(path) catch return 2;
        }
    }
    return 0;
}

// --- hash & random ---
fn fnv1a64(data: []const u8) u64 {
    var h: u64 = 0xcbf29ce484222325;
    for (data) |b| {
        h ^= b;
        h *%= 0x100000001b3;
    }
    return h;
}

fn crc32IEEE(data: []const u8) u32 {
    var crc: u32 = 0xFFFFFFFF;
    for (data) |b| {
        crc ^= b;
        var i: u8 = 0;
        while (i < 8) : (i += 1) {
            if (crc & 1 == 1) {
                crc = (crc >> 1) ^ 0xEDB88320;
            } else {
                crc >>= 1;
            }
        }
    }
    return ~crc;
}

pub export fn sa_bun_plugin_hash_u64(data_ptr: ?[*]const u8, data_len: u64, algo: u32, out_hash: ?*u64) u32 {
    if (data_ptr == null) return 2;
    const slot = out_hash orelse return 2;
    const data = data_ptr.?[0..data_len];
    switch (algo) {
        0 => slot.* = fnv1a64(data), // BUN_HASH_FNV1A64
        1 => slot.* = crc32IEEE(data), // BUN_HASH_CRC32 (zero-extended)
        2 => slot.* = bun_hash.wyhashFinal4(0, data), // BUN_HASH_WYHASH64, seed 0 = Bun.hash(data)
        3 => slot.* = bun_hash.xxhash64(0, data), // BUN_HASH_XXHASH64, seed 0
        else => return 2,
    }
    return 0;
}

pub export fn sa_bun_plugin_hash_crc32(data_ptr: ?[*]const u8, data_len: u64, out_crc: ?*u32) u32 {
    if (data_ptr == null) return 2;
    const slot = out_crc orelse return 2;
    slot.* = crc32IEEE(data_ptr.?[0..data_len]);
    return 0;
}

pub export fn sa_bun_plugin_sha256_hex(data_ptr: ?[*]const u8, data_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    if (data_ptr == null) return 2;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data_ptr.?[0..data_len], &digest, .{});
    var hex_buf: [64]u8 = undefined;
    const hex = std.fmt.bufPrint(&hex_buf, "{s}", .{std.fmt.fmtSliceHexLower(&digest)}) catch return 2;
    return writeOwned(out_ptr, out_len, hex);
}

pub export fn sa_bun_plugin_sha512_hex(data_ptr: ?[*]const u8, data_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    if (data_ptr == null) return 2;
    var digest: [64]u8 = undefined;
    std.crypto.hash.sha2.Sha512.hash(data_ptr.?[0..data_len], &digest, .{});
    var hex_buf: [128]u8 = undefined;
    const hex = std.fmt.bufPrint(&hex_buf, "{s}", .{std.fmt.fmtSliceHexLower(&digest)}) catch return 2;
    return writeOwned(out_ptr, out_len, hex);
}

pub export fn sa_bun_plugin_random_bytes(size: u64, out_ptr: ?*?[*]const u8) u32 {
    if (size == 0 or size > 1024 * 1024) return 2;
    const n: usize = @intCast(size);
    const buf = std.heap.page_allocator.alloc(u8, n) catch return 2;
    errdefer std.heap.page_allocator.free(buf);
    std.crypto.random.bytes(buf);
    const slot = out_ptr orelse {
        std.heap.page_allocator.free(buf);
        return 2;
    };
    slot.* = buf.ptr;
    return 0;
}

pub export fn sa_bun_plugin_random_uuid_v7(out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    var rand: [16]u8 = undefined;
    std.crypto.random.bytes(&rand);
    const ms: u64 = @intCast(@max(std.time.milliTimestamp(), 0));
    rand[0] = @intCast((ms >> 40) & 0xFF);
    rand[1] = @intCast((ms >> 32) & 0xFF);
    rand[2] = @intCast((ms >> 24) & 0xFF);
    rand[3] = @intCast((ms >> 16) & 0xFF);
    rand[4] = @intCast((ms >> 8) & 0xFF);
    rand[5] = @intCast(ms & 0xFF);
    rand[6] = (rand[6] & 0x0F) | 0x70; // version 7
    rand[8] = (rand[8] & 0x3F) | 0x80; // variant 10
    var text: [36]u8 = undefined;
    const hex = "0123456789abcdef";
    var ti: usize = 0;
    for (rand, 0..) |b, i| {
        if (i == 4 or i == 6 or i == 8 or i == 10) {
            text[ti] = '-';
            ti += 1;
        }
        text[ti] = hex[b >> 4];
        text[ti + 1] = hex[b & 0xF];
        ti += 2;
    }
    return writeOwned(out_ptr, out_len, &text);
}

// --- compression: Bun.gzipSync / gunzipSync / deflateSync / inflateSync ---
pub export fn sa_bun_plugin_gzip_compress(data_ptr: ?[*]const u8, data_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    if (data_ptr == null) return 2;
    const d = data_ptr.?[0..data_len];
    var out_list = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer out_list.deinit();
    var compressor = std.compress.gzip.compressor(out_list.writer(), .{}) catch return 2;
    compressor.writer().writeAll(d) catch return 2;
    compressor.finish() catch return 2;
    const slice = out_list.toOwnedSlice() catch return 2;
    const ptr_slot = out_ptr orelse {
        std.heap.page_allocator.free(slice);
        return 2;
    };
    const len_slot = out_len orelse {
        std.heap.page_allocator.free(slice);
        return 2;
    };
    ptr_slot.* = slice.ptr;
    len_slot.* = slice.len;
    return 0;
}

pub export fn sa_bun_plugin_gzip_decompress(data_ptr: ?[*]const u8, data_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    if (data_ptr == null) return 2;
    const d = data_ptr.?[0..data_len];
    var in_stream = std.io.fixedBufferStream(d);
    var decompressor = std.compress.gzip.decompressor(in_stream.reader());
    var out_list = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer out_list.deinit();
    var temp_buf: [4096]u8 = undefined;
    while (true) {
        const n = decompressor.read(&temp_buf) catch return 2;
        if (n == 0) break;
        out_list.appendSlice(temp_buf[0..n]) catch return 2;
    }
    const slice = out_list.toOwnedSlice() catch return 2;
    const ptr_slot = out_ptr orelse {
        std.heap.page_allocator.free(slice);
        return 2;
    };
    const len_slot = out_len orelse {
        std.heap.page_allocator.free(slice);
        return 2;
    };
    ptr_slot.* = slice.ptr;
    len_slot.* = slice.len;
    return 0;
}

pub export fn sa_bun_plugin_deflate_compress(data_ptr: ?[*]const u8, data_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    if (data_ptr == null) return 2;
    const d = data_ptr.?[0..data_len];
    var out_list = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer out_list.deinit();
    var compressor = std.compress.flate.compressor(out_list.writer(), .{}) catch return 2;
    compressor.writer().writeAll(d) catch return 2;
    compressor.finish() catch return 2;
    const slice = out_list.toOwnedSlice() catch return 2;
    const ptr_slot = out_ptr orelse {
        std.heap.page_allocator.free(slice);
        return 2;
    };
    const len_slot = out_len orelse {
        std.heap.page_allocator.free(slice);
        return 2;
    };
    ptr_slot.* = slice.ptr;
    len_slot.* = slice.len;
    return 0;
}

pub export fn sa_bun_plugin_deflate_decompress(data_ptr: ?[*]const u8, data_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    if (data_ptr == null) return 2;
    const d = data_ptr.?[0..data_len];
    var in_stream = std.io.fixedBufferStream(d);
    var decompressor = std.compress.flate.decompressor(in_stream.reader());
    var out_list = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer out_list.deinit();
    var temp_buf: [4096]u8 = undefined;
    while (true) {
        const n = decompressor.reader().read(&temp_buf) catch return 2;
        if (n == 0) break;
        out_list.appendSlice(temp_buf[0..n]) catch return 2;
    }
    const slice = out_list.toOwnedSlice() catch return 2;
    const ptr_slot = out_ptr orelse {
        std.heap.page_allocator.free(slice);
        return 2;
    };
    const len_slot = out_len orelse {
        std.heap.page_allocator.free(slice);
        return 2;
    };
    ptr_slot.* = slice.ptr;
    len_slot.* = slice.len;
    return 0;
}

// --- text ---
pub export fn sa_bun_plugin_escape_html(data_ptr: ?[*]const u8, data_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    if (data_ptr == null) return 2;
    const data = data_ptr.?[0..data_len];
    var list = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer list.deinit();
    for (data) |c| {
        switch (c) {
            '&' => list.appendSlice("&amp;") catch return 2,
            '<' => list.appendSlice("&lt;") catch return 2,
            '>' => list.appendSlice("&gt;") catch return 2,
            '"' => list.appendSlice("&quot;") catch return 2,
            '\'' => list.appendSlice("&#x27;") catch return 2,
            '`' => list.appendSlice("&#x60;") catch return 2,
            else => list.append(c) catch return 2,
        }
    }
    const slice = list.toOwnedSlice() catch return 2;
    defer std.heap.page_allocator.free(slice);
    return writeOwned(out_ptr, out_len, slice);
}

fn isWide(cp: u21) bool {
    return (cp >= 0x1100 and cp <= 0x115F) or
        (cp >= 0x2E80 and cp <= 0x303E) or
        (cp >= 0x3041 and cp <= 0x33FF) or
        (cp >= 0x3400 and cp <= 0x4DBF) or
        (cp >= 0x4E00 and cp <= 0xA4CF) or
        (cp >= 0xAC00 and cp <= 0xD7A3) or
        (cp >= 0xF900 and cp <= 0xFAFF) or
        (cp >= 0xFE30 and cp <= 0xFE4F) or
        (cp >= 0xFF00 and cp <= 0xFF60) or
        (cp >= 0xFFE0 and cp <= 0xFFE6) or
        (cp >= 0x1F300 and cp <= 0x1FAFF) or
        (cp >= 0x20000 and cp <= 0x3FFFD);
}

pub export fn sa_bun_plugin_string_width(data_ptr: ?[*]const u8, data_len: u64, out_width: ?*u64) u32 {
    if (data_ptr == null) return 2;
    const slot = out_width orelse return 2;
    const data = data_ptr.?[0..data_len];
    var width: u64 = 0;
    var i: usize = 0;
    while (i < data.len) {
        const len = std.unicode.utf8ByteSequenceLength(data[i]) catch return 2;
        if (i + len > data.len) return 2;
        const cp = std.unicode.utf8Decode(data[i .. i + len]) catch return 2;
        width += if (isWide(cp)) 2 else 1;
        i += len;
    }
    slot.* = width;
    return 0;
}

pub export fn sa_bun_plugin_btoa(data_ptr: ?[*]const u8, data_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    if (data_ptr == null) return 2;
    const bytes = data_ptr.?[0..data_len];
    // bytes are already Latin-1 by construction; no range check needed.
    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const encoded = std.heap.page_allocator.alloc(u8, encoded_len) catch return 2;
    errdefer std.heap.page_allocator.free(encoded);
    _ = std.base64.standard.Encoder.encode(encoded, bytes);
    const ptr_slot = out_ptr orelse {
        std.heap.page_allocator.free(encoded);
        return 2;
    };
    const len_slot = out_len orelse {
        std.heap.page_allocator.free(encoded);
        return 2;
    };
    ptr_slot.* = encoded.ptr;
    len_slot.* = encoded.len;
    return 0;
}

pub export fn sa_bun_plugin_atob(data_ptr: ?[*]const u8, data_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    if (data_ptr == null or data_len == 0) return 2;
    const enc = data_ptr.?[0..data_len];
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(enc) catch return 2;
    const decoded = std.heap.page_allocator.alloc(u8, decoded_len) catch return 2;
    errdefer std.heap.page_allocator.free(decoded);
    std.base64.standard.Decoder.decode(decoded, enc) catch {
        std.heap.page_allocator.free(decoded);
        return 2;
    };
    const ptr_slot = out_ptr orelse {
        std.heap.page_allocator.free(decoded);
        return 2;
    };
    const len_slot = out_len orelse {
        std.heap.page_allocator.free(decoded);
        return 2;
    };
    ptr_slot.* = decoded.ptr;
    len_slot.* = decoded.len;
    return 0;
}

// --- process: Bun.spawnSync (sync subset) ---
fn skipWs(s: []const u8, i: *usize) void {
    while (i.* < s.len and (s[i.*] == ' ' or s[i.*] == '\t' or s[i.*] == '\n' or s[i.*] == '\r')) {
        i.* += 1;
    }
}

// Parses a JSON array of strings: ["prog","arg",...]. Returns owned argv (caller frees).
fn parseArgvJson(json: []const u8) ![][]const u8 {
    var argv = std.array_list.Managed([]const u8).init(std.heap.page_allocator);
    errdefer {
        for (argv.items) |a| std.heap.page_allocator.free(a);
        argv.deinit();
    }
    var i: usize = 0;
    skipWs(json, &i);
    if (i >= json.len or json[i] != '[') return error.InvalidArgv;
    i += 1;
    while (true) {
        skipWs(json, &i);
        if (i >= json.len) return error.InvalidArgv;
        if (json[i] == ']') {
            i += 1;
            break;
        }
        if (json[i] != '"') return error.InvalidArgv;
        i += 1;
        var cur = std.array_list.Managed(u8).init(std.heap.page_allocator);
        errdefer cur.deinit();
        while (i < json.len and json[i] != '"') {
            if (json[i] == '\\') {
                i += 1;
                if (i >= json.len) return error.InvalidArgv;
                switch (json[i]) {
                    '"', '\\', '/' => try cur.append(json[i]),
                    'n' => try cur.append('\n'),
                    't' => try cur.append('\t'),
                    'r' => try cur.append('\r'),
                    else => return error.InvalidArgv,
                }
            } else {
                try cur.append(json[i]);
            }
            i += 1;
        }
        if (i >= json.len) return error.InvalidArgv;
        i += 1; // closing quote
        try argv.append(try cur.toOwnedSlice());
        skipWs(json, &i);
        if (i < json.len and json[i] == ',') {
            i += 1;
            continue;
        }
        if (i < json.len and json[i] == ']') {
            i += 1;
            break;
        }
        if (i >= json.len) return error.InvalidArgv;
        return error.InvalidArgv;
    }
    return argv.toOwnedSlice();
}

pub export fn sa_bun_plugin_spawn_sync(argv_json_ptr: ?[*]const u8, argv_json_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_code: ?*u32, out_stdout_ptr: ?*?[*]const u8, out_stdout_len: ?*u64, out_stderr_ptr: ?*?[*]const u8, out_stderr_len: ?*u64) u32 {
    if (argv_json_ptr == null or argv_json_len == 0) return 2;
    const code_slot = out_code orelse return 2;
    const allocator = std.heap.page_allocator;
    const argv_json = argv_json_ptr.?[0..argv_json_len];
    const argv = parseArgvJson(argv_json) catch return 2;
    defer {
        for (argv) |a| allocator.free(a);
        allocator.free(argv);
    }
    if (argv.len == 0) return 2;
    var cwd: ?[]const u8 = null;
    if (cwd_ptr != null and cwd_len > 0) {
        cwd = cwd_ptr.?[0..cwd_len];
    }
    const run_res = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .cwd = cwd,
        .max_output_bytes = 10 * 1024 * 1024,
    }) catch return 2;
    switch (run_res.term) {
        .Exited => |code| code_slot.* = code,
        else => code_slot.* = 1,
    }
    (out_stdout_ptr orelse return 2).* = run_res.stdout.ptr;
    (out_stdout_len orelse return 2).* = run_res.stdout.len;
    (out_stderr_ptr orelse return 2).* = run_res.stderr.ptr;
    (out_stderr_len orelse return 2).* = run_res.stderr.len;
    return 0;
}

pub export fn sa_bun_plugin_resolve_sync(spec_ptr: ?[*]const u8, spec_len: u64, parent_ptr: ?[*]const u8, parent_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    if (spec_ptr == null or spec_len == 0) return 2;
    const spec = spec_ptr.?[0..spec_len];
    if (std.fs.path.isAbsolute(spec)) {
        return writeOwned(out_ptr, out_len, spec);
    }
    var parent_dir: []const u8 = ".";
    if (parent_ptr != null and parent_len > 0) {
        const parent = parent_ptr.?[0..parent_len];
        parent_dir = std.fs.path.dirname(parent) orelse ".";
    }
    if (std.mem.startsWith(u8, spec, "./") or std.mem.startsWith(u8, spec, "../") or std.mem.eql(u8, spec, ".") or std.mem.eql(u8, spec, "..")) {
        const joined = std.fs.path.join(std.heap.page_allocator, &.{ parent_dir, spec }) catch return 2;
        defer std.heap.page_allocator.free(joined);
        return writeOwned(out_ptr, out_len, joined);
    }
    return 1; // bare specifiers need node_modules / Bun resolver: not native
}

pub export fn sa_bun_plugin_shell_escape(data_ptr: ?[*]const u8, data_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    if (data_ptr == null) return 2;
    const data = data_ptr.?[0..data_len];
    var list = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer list.deinit();
    list.append('\'') catch return 2;
    for (data) |c| {
        if (c == '\'') {
            list.appendSlice("'\\''") catch return 2;
        } else {
            list.append(c) catch return 2;
        }
    }
    list.append('\'') catch return 2;
    const slice = list.toOwnedSlice() catch return 2;
    defer std.heap.page_allocator.free(slice);
    return writeOwned(out_ptr, out_len, slice);
}

// --- seeded one-shot hashes: Bun.hash.wyhash / xxHash64 / xxHash32 / adler32 ---
// Upstream: src/runtime/api/HashObject.rs (seed default 0), src/wyhash/lib.rs,
// src/hash/xxhash.rs + src/highway ("bit-identical to the xxHash reference").
pub export fn sa_bun_plugin_hash_wyhash64(data_ptr: ?[*]const u8, data_len: u64, seed: u64, out_hash: ?*u64) u32 {
    if (data_ptr == null) return 2;
    const slot = out_hash orelse return 2;
    slot.* = bun_hash.wyhashFinal4(seed, data_ptr.?[0..data_len]);
    return 0;
}

pub export fn sa_bun_plugin_hash_xxhash64(data_ptr: ?[*]const u8, data_len: u64, seed: u64, out_hash: ?*u64) u32 {
    if (data_ptr == null) return 2;
    const slot = out_hash orelse return 2;
    slot.* = bun_hash.xxhash64(seed, data_ptr.?[0..data_len]);
    return 0;
}

pub export fn sa_bun_plugin_hash_xxhash32(data_ptr: ?[*]const u8, data_len: u64, seed: u32, out_hash: ?*u32) u32 {
    if (data_ptr == null) return 2;
    const slot = out_hash orelse return 2;
    slot.* = bun_hash.xxhash32(seed, data_ptr.?[0..data_len]);
    return 0;
}

pub export fn sa_bun_plugin_hash_adler32(data_ptr: ?[*]const u8, data_len: u64, out_hash: ?*u32) u32 {
    if (data_ptr == null) return 2;
    const slot = out_hash orelse return 2;
    slot.* = bun_hash.adler32(data_ptr.?[0..data_len]);
    return 0;
}

// --- incremental hasher: Bun.CryptoHasher subset (sha256/sha512/sha1/md5) ---
// algo: 0 = sha256, 1 = sha512, 2 = sha1, 3 = md5. Handle is an owned pointer.
const HasherCtx = struct {
    algo: u32,
    sha256: std.crypto.hash.sha2.Sha256,
    sha512: std.crypto.hash.sha2.Sha512,
    sha1: std.crypto.hash.Sha1,
    md5: std.crypto.hash.Md5,
};

pub export fn sa_bun_plugin_hasher_new(algo: u32, out_handle: ?*?*anyopaque) u32 {
    if (algo > 3) return 2;
    const slot = out_handle orelse return 2;
    const ctx = std.heap.page_allocator.create(HasherCtx) catch return 2;
    ctx.algo = algo;
    switch (algo) {
        0 => ctx.sha256 = std.crypto.hash.sha2.Sha256.init(.{}),
        1 => ctx.sha512 = std.crypto.hash.sha2.Sha512.init(.{}),
        2 => ctx.sha1 = std.crypto.hash.Sha1.init(.{}),
        else => ctx.md5 = std.crypto.hash.Md5.init(.{}),
    }
    slot.* = ctx;
    return 0;
}

pub export fn sa_bun_plugin_hasher_update(handle: ?*anyopaque, data_ptr: ?[*]const u8, data_len: u64) u32 {
    const ctx: *HasherCtx = @ptrCast(@alignCast(handle orelse return 2));
    const data = if (data_ptr) |p| p[0..data_len] else return 2;
    switch (ctx.algo) {
        0 => ctx.sha256.update(data),
        1 => ctx.sha512.update(data),
        2 => ctx.sha1.update(data),
        else => ctx.md5.update(data),
    }
    return 0;
}

pub export fn sa_bun_plugin_hasher_digest_hex(handle: ?*anyopaque, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    const ctx: *HasherCtx = @ptrCast(@alignCast(handle orelse return 2));
    var digest: [64]u8 = undefined;
    const n: usize = switch (ctx.algo) {
        0 => blk: {
            ctx.sha256.final(digest[0..32]);
            break :blk 32;
        },
        1 => blk: {
            ctx.sha512.final(digest[0..64]);
            break :blk 64;
        },
        2 => blk: {
            ctx.sha1.final(digest[0..20]);
            break :blk 20;
        },
        else => blk: {
            ctx.md5.final(digest[0..16]);
            break :blk 16;
        },
    };
    var hex_buf: [128]u8 = undefined;
    const hex = std.fmt.bufPrint(&hex_buf, "{s}", .{std.fmt.fmtSliceHexLower(digest[0..n])}) catch return 2;
    return writeOwned(out_ptr, out_len, hex);
}

pub export fn sa_bun_plugin_hasher_free(handle: ?*anyopaque) u32 {
    const ctx: *HasherCtx = @ptrCast(@alignCast(handle orelse return 2));
    std.heap.page_allocator.destroy(ctx);
    return 0;
}

// --- HMAC-SHA256 + S3 SigV4 signing key path ---
pub export fn sa_bun_plugin_hmac_sha256_hex(key_ptr: ?[*]const u8, key_len: u64, data_ptr: ?[*]const u8, data_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    if (key_ptr == null or data_ptr == null) return 2;
    var digest: [32]u8 = undefined;
    std.crypto.auth.hmac.sha2.HmacSha256.create(&digest, data_ptr.?[0..data_len], key_ptr.?[0..key_len]);
    var hex_buf: [64]u8 = undefined;
    const hex = std.fmt.bufPrint(&hex_buf, "{s}", .{std.fmt.fmtSliceHexLower(&digest)}) catch return 2;
    return writeOwned(out_ptr, out_len, hex);
}

// AWS Signature Version 4 signing-key derivation:
//   kSigning = HMAC(HMAC(HMAC(HMAC("AWS4"+secret, date), region), service), "aws4_request")
//   signature = hex(HMAC(kSigning, stringToSign))
pub export fn sa_bun_plugin_s3_sigv4_signature(secret_ptr: ?[*]const u8, secret_len: u64, date_ptr: ?[*]const u8, date_len: u64, region_ptr: ?[*]const u8, region_len: u64, service_ptr: ?[*]const u8, service_len: u64, sts_ptr: ?[*]const u8, sts_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    if (secret_ptr == null or date_ptr == null or region_ptr == null or service_ptr == null or sts_ptr == null) return 2;
    const H = std.crypto.auth.hmac.sha2.HmacSha256;
    var k_secret: [128]u8 = undefined;
    if (secret_len + 4 > k_secret.len) return 2;
    @memcpy(k_secret[0..4], "AWS4");
    @memcpy(k_secret[4 .. 4 + secret_len], secret_ptr.?[0..secret_len]);
    var k_date: [32]u8 = undefined;
    H.create(&k_date, date_ptr.?[0..date_len], k_secret[0 .. 4 + secret_len]);
    var k_region: [32]u8 = undefined;
    H.create(&k_region, region_ptr.?[0..region_len], &k_date);
    var k_service: [32]u8 = undefined;
    H.create(&k_service, service_ptr.?[0..service_len], &k_region);
    var k_signing: [32]u8 = undefined;
    H.create(&k_signing, "aws4_request", &k_service);
    var sig: [32]u8 = undefined;
    H.create(&sig, sts_ptr.?[0..sts_len], &k_signing);
    var hex_buf: [64]u8 = undefined;
    const hex = std.fmt.bufPrint(&hex_buf, "{s}", .{std.fmt.fmtSliceHexLower(&sig)}) catch return 2;
    return writeOwned(out_ptr, out_len, hex);
}

// --- semver: Bun.semver subset (numeric core + prerelease ordering) ---
fn parseSemverNum(part: []const u8) ?u64 {
    if (part.len == 0) return null;
    var v: u64 = 0;
    for (part) |c| {
        if (c < '0' or c > '9') return null;
        v = v * 10 + (c - '0');
    }
    return v;
}

fn semverOrder(a: []const u8, b: []const u8) ?i32 {
    var aa = a;
    var bb = b;
    if (aa.len > 0 and aa[0] == 'v') aa = aa[1..];
    if (bb.len > 0 and bb[0] == 'v') bb = bb[1..];
    // split core vs prerelease (cut build metadata first)
    const a_core = blk: {
        var core = aa;
        if (std.mem.indexOfScalar(u8, core, '+')) |i| core = core[0..i];
        if (std.mem.indexOfScalar(u8, core, '-')) |i| core = core[0..i];
        break :blk core;
    };
    const b_core = blk: {
        var core = bb;
        if (std.mem.indexOfScalar(u8, core, '+')) |i| core = core[0..i];
        if (std.mem.indexOfScalar(u8, core, '-')) |i| core = core[0..i];
        break :blk core;
    };
    var ait = std.mem.splitScalar(u8, a_core, '.');
    var bit = std.mem.splitScalar(u8, b_core, '.');
    var depth: usize = 0;
    while (depth < 3) : (depth += 1) {
        const ap = ait.next() orelse "0";
        const bp = bit.next() orelse "0";
        const av = parseSemverNum(ap) orelse return null;
        const bv = parseSemverNum(bp) orelse return null;
        if (av < bv) return -1;
        if (av > bv) return 1;
    }
    const a_pre = blk: {
        var rest = aa;
        if (std.mem.indexOfScalar(u8, rest, '+')) |i| rest = rest[0..i];
        if (std.mem.indexOfScalar(u8, rest, '-')) |i| break :blk rest[i + 1 ..];
        break :blk @as([]const u8, "");
    };
    const b_pre = blk: {
        var rest = bb;
        if (std.mem.indexOfScalar(u8, rest, '+')) |i| rest = rest[0..i];
        if (std.mem.indexOfScalar(u8, rest, '-')) |i| break :blk rest[i + 1 ..];
        break :blk @as([]const u8, "");
    };
    if (a_pre.len == 0 and b_pre.len == 0) return 0;
    if (a_pre.len == 0) return 1; // release > prerelease
    if (b_pre.len == 0) return -1;
    // identifier-by-identifier: numeric < alphanumeric, numeric compares numerically
    var ai = std.mem.splitScalar(u8, a_pre, '.');
    var bi = std.mem.splitScalar(u8, b_pre, '.');
    while (true) {
        const an = ai.next();
        const bn = bi.next();
        if (an == null and bn == null) return 0;
        if (an == null) return -1;
        if (bn == null) return 1;
        const av = parseSemverNum(an.?);
        const bv = parseSemverNum(bn.?);
        if (av != null and bv != null) {
            if (av.? < bv.?) return -1;
            if (av.? > bv.?) return 1;
        } else if (av != null) {
            return -1; // numeric < alphanumeric
        } else if (bv != null) {
            return 1;
        } else {
            const ord = std.mem.order(u8, an.?, bn.?);
            if (ord == .lt) return -1;
            if (ord == .gt) return 1;
        }
    }
}

pub export fn sa_bun_plugin_semver_cmp(a_ptr: ?[*]const u8, a_len: u64, b_ptr: ?[*]const u8, b_len: u64, out_order: ?*i32) u32 {
    if (a_ptr == null or b_ptr == null) return 2;
    const slot = out_order orelse return 2;
    slot.* = semverOrder(a_ptr.?[0..a_len], b_ptr.?[0..b_len]) orelse return 2;
    return 0;
}

// --- shell: Bun.$ sync subset (sh -c, captures code/stdout/stderr) ---
pub export fn sa_bun_plugin_shell_exec(cmd_ptr: ?[*]const u8, cmd_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_code: ?*u32, out_stdout_ptr: ?*?[*]const u8, out_stdout_len: ?*u64, out_stderr_ptr: ?*?[*]const u8, out_stderr_len: ?*u64) u32 {
    if (cmd_ptr == null or cmd_len == 0) return 2;
    const code_slot = out_code orelse return 2;
    const allocator = std.heap.page_allocator;
    const cmd = cmd_ptr.?[0..cmd_len];
    var cwd: ?[]const u8 = null;
    if (cwd_ptr != null and cwd_len > 0) {
        cwd = cwd_ptr.?[0..cwd_len];
    }
    const argv = [_][]const u8{ "/bin/sh", "-c", cmd };
    const run_res = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &argv,
        .cwd = cwd,
        .max_output_bytes = 10 * 1024 * 1024,
    }) catch return 2;
    switch (run_res.term) {
        .Exited => |code| code_slot.* = code,
        else => code_slot.* = 1,
    }
    (out_stdout_ptr orelse return 2).* = run_res.stdout.ptr;
    (out_stdout_len orelse return 2).* = run_res.stdout.len;
    (out_stderr_ptr orelse return 2).* = run_res.stderr.ptr;
    (out_stderr_len orelse return 2).* = run_res.stderr.len;
    return 0;
}

// --- stdio sink: Bun.write(Bun.stdout, ...) / Bun.write(Bun.stderr, ...) ---
pub export fn sa_bun_plugin_write_stdout(data_ptr: ?[*]const u8, data_len: u64) u32 {
    if (data_ptr == null) return 2;
    std.io.getStdOut().writeAll(data_ptr.?[0..data_len]) catch return 2;
    return 0;
}

pub export fn sa_bun_plugin_write_stderr(data_ptr: ?[*]const u8, data_len: u64) u32 {
    if (data_ptr == null) return 2;
    std.io.getStdErr().writeAll(data_ptr.?[0..data_len]) catch return 2;
    return 0;
}

// --- capability snapshots (honest stubs) ---
pub export fn sa_bun_plugin_serve_support_json(out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    return writeOwned(out_ptr, out_len,
        \\{"surface":"Bun.serve","status":"delegated","routes":"BUN_SERVE_NEW/START/ACCEPT via sa_http_server_* macros in bun.sal","websocket":"frame-level only via NET_WS_* macros","note":"no JS fetch-handler runtime; handlers are SA call sites"}
    );
}

pub export fn sa_bun_plugin_sqlite_support_json(out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    return writeOwned(out_ptr, out_len,
        \\{"surface":"bun:sqlite","status":"unsupported","reason":"needs embedded SQLite engine; use sa_plugin_db instead"}
    );
}

pub export fn sa_bun_plugin_s3_support_json(out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    return writeOwned(out_ptr, out_len,
        \\{"surface":"Bun.S3","status":"unsupported","reason":"needs S3 SigV4 + async IO subsystem; use sa_http_client_* directly"}
    );
}

pub export fn sa_bun_plugin_redis_support_json(out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    return writeOwned(out_ptr, out_len,
        \\{"surface":"Bun.RedisClient","status":"unsupported","reason":"needs RESP3 async client; no native surface yet"}
    );
}

pub export fn sa_bun_plugin_ffi_support_json(out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    return writeOwned(out_ptr, out_len,
        \\{"surface":"bun:ffi","status":"unsupported","reason":"needs dlopen/FFI type bridge; see sa_plugin_bc2sa for bitcode migration path"}
    );
}

pub export fn sa_bun_plugin_build_support_json(out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    return writeOwned(out_ptr, out_len,
        \\{"surface":"Bun.build/Transpiler/plugin","status":"unsupported","reason":"needs JS bundler subsystem; see sa_plugin_sax/sa_plugin_vite for SA-side builds"}
    );
}

pub export fn sa_bun_plugin_test_support_json(out_ptr: ?*?[*]const u8, out_len: ?*u64) u32 {
    return writeOwned(out_ptr, out_len,
        \\{"surface":"bun:test","status":"unsupported","reason":"use native sa test workflow; no describe/it/expect object model"}
    );
}
