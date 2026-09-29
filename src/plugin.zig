const std = @import("std");
const plugin_api = @import("plugin_api");
pub usingnamespace @import("bun_saasm_api.zig");

const skills = [_]plugin_api.SkillSection{
    .{
        .name = "bun-compat",
        .summary = "Bun API compatibility layer exposed via dynamically loaded dynamic library.",
        .items = &.{
            "bun version, revision, main, argv, cwd, which",
            "bun file read/write text+base64, size, exists, mkdir, remove",
            "bun fileURLToPath, pathToFileURL, nanoseconds, sleepSync",
            "bun env get, set, delete (Bun.env parity)",
            "bun hash u64, crc32, sha256/sha512 hex, randomBytes, randomUUIDv7",
            "bun wyhash(final4)/xxhash64/xxhash32/adler32 seeded, CryptoHasher, HMAC-SHA256",
            "bun S3 SigV4 signing, semver cmp, shell exec, stdout/stderr write",
            "bun serve accept/respond + websocket upgrade/read/write via http-server",
            "bun gzip/gunzip/deflate/inflate sync, escapeHTML, stringWidth, btoa/atob",
            "bun spawnSync, resolveSync, shell escape",
            "bun serve/sqlite/s3/redis/ffi/build/test capability snapshots",
            "public SA interface files: bun.sai and bun.sal",
        },
    },
};

pub const plugin = plugin_api.Plugin{
    .name = "bun",
    .skills = &skills,
};

pub const descriptor = plugin_api.PluginDescriptor{
    .abi_version = plugin_api.abi_version,
    .descriptor_size = @as(u32, @intCast(@sizeOf(plugin_api.PluginDescriptor))),
    .name = "bun",
    .init = null,
    .prebuild = null,
    .postbuild = null,
    .handle_command = null,
    .skills_ptr = skills[0..].ptr,
    .skills_len = skills.len,
};

pub export const saasm_plugin_descriptor_v1: plugin_api.PluginDescriptor = descriptor;

pub export fn saasm_plugin_descriptor_v1_fn(out: *plugin_api.PluginDescriptor) callconv(.c) void {
    out.* = descriptor;
}
