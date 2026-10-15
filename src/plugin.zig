const std = @import("std");
const plugin_api = @import("plugin_api");
const _api = @import("bun_saasm_api.zig");
// NOTE(Zig 0.17): usingnamespace removed.
pub const sa_bun_plugin_free_buffer = _api.sa_bun_plugin_free_buffer;
pub const sa_bun_plugin_version = _api.sa_bun_plugin_version;
pub const sa_bun_plugin_revision = _api.sa_bun_plugin_revision;
pub const sa_bun_plugin_main = _api.sa_bun_plugin_main;
pub const sa_bun_plugin_argv_json = _api.sa_bun_plugin_argv_json;
pub const sa_bun_plugin_cwd = _api.sa_bun_plugin_cwd;
pub const sa_bun_plugin_which = _api.sa_bun_plugin_which;
pub const sa_bun_plugin_file_url_to_path = _api.sa_bun_plugin_file_url_to_path;
pub const sa_bun_plugin_path_to_file_url = _api.sa_bun_plugin_path_to_file_url;
pub const sa_bun_plugin_nanoseconds = _api.sa_bun_plugin_nanoseconds;
pub const sa_bun_plugin_sleep_sync = _api.sa_bun_plugin_sleep_sync;
pub const sa_bun_plugin_env_get = _api.sa_bun_plugin_env_get;
pub const sa_bun_plugin_env_set = _api.sa_bun_plugin_env_set;
pub const sa_bun_plugin_env_delete = _api.sa_bun_plugin_env_delete;
pub const sa_bun_plugin_file_read_text = _api.sa_bun_plugin_file_read_text;
pub const sa_bun_plugin_file_read_base64 = _api.sa_bun_plugin_file_read_base64;
pub const sa_bun_plugin_write_text_file = _api.sa_bun_plugin_write_text_file;
pub const sa_bun_plugin_write_file_base64 = _api.sa_bun_plugin_write_file_base64;
pub const sa_bun_plugin_file_size = _api.sa_bun_plugin_file_size;
pub const sa_bun_plugin_file_exists = _api.sa_bun_plugin_file_exists;
pub const sa_bun_plugin_mkdir = _api.sa_bun_plugin_mkdir;
pub const sa_bun_plugin_remove = _api.sa_bun_plugin_remove;
pub const sa_bun_plugin_hash_u64 = _api.sa_bun_plugin_hash_u64;
pub const sa_bun_plugin_hash_crc32 = _api.sa_bun_plugin_hash_crc32;
pub const sa_bun_plugin_sha256_hex = _api.sa_bun_plugin_sha256_hex;
pub const sa_bun_plugin_sha512_hex = _api.sa_bun_plugin_sha512_hex;
pub const sa_bun_plugin_random_bytes = _api.sa_bun_plugin_random_bytes;
pub const sa_bun_plugin_random_uuid_v7 = _api.sa_bun_plugin_random_uuid_v7;
pub const sa_bun_plugin_gzip_compress = _api.sa_bun_plugin_gzip_compress;
pub const sa_bun_plugin_gzip_decompress = _api.sa_bun_plugin_gzip_decompress;
pub const sa_bun_plugin_deflate_compress = _api.sa_bun_plugin_deflate_compress;
pub const sa_bun_plugin_deflate_decompress = _api.sa_bun_plugin_deflate_decompress;
pub const sa_bun_plugin_escape_html = _api.sa_bun_plugin_escape_html;
pub const sa_bun_plugin_string_width = _api.sa_bun_plugin_string_width;
pub const sa_bun_plugin_btoa = _api.sa_bun_plugin_btoa;
pub const sa_bun_plugin_atob = _api.sa_bun_plugin_atob;
pub const sa_bun_plugin_spawn_sync = _api.sa_bun_plugin_spawn_sync;
pub const sa_bun_plugin_resolve_sync = _api.sa_bun_plugin_resolve_sync;
pub const sa_bun_plugin_shell_escape = _api.sa_bun_plugin_shell_escape;
pub const sa_bun_plugin_hash_wyhash64 = _api.sa_bun_plugin_hash_wyhash64;
pub const sa_bun_plugin_hash_xxhash64 = _api.sa_bun_plugin_hash_xxhash64;
pub const sa_bun_plugin_hash_xxhash32 = _api.sa_bun_plugin_hash_xxhash32;
pub const sa_bun_plugin_hash_adler32 = _api.sa_bun_plugin_hash_adler32;
pub const sa_bun_plugin_hasher_new = _api.sa_bun_plugin_hasher_new;
pub const sa_bun_plugin_hasher_update = _api.sa_bun_plugin_hasher_update;
pub const sa_bun_plugin_hasher_digest_hex = _api.sa_bun_plugin_hasher_digest_hex;
pub const sa_bun_plugin_hasher_free = _api.sa_bun_plugin_hasher_free;
pub const sa_bun_plugin_hmac_sha256_hex = _api.sa_bun_plugin_hmac_sha256_hex;
pub const sa_bun_plugin_s3_sigv4_signature = _api.sa_bun_plugin_s3_sigv4_signature;
pub const sa_bun_plugin_semver_cmp = _api.sa_bun_plugin_semver_cmp;
pub const sa_bun_plugin_shell_exec = _api.sa_bun_plugin_shell_exec;
pub const sa_bun_plugin_write_stdout = _api.sa_bun_plugin_write_stdout;
pub const sa_bun_plugin_write_stderr = _api.sa_bun_plugin_write_stderr;
pub const sa_bun_plugin_serve_support_json = _api.sa_bun_plugin_serve_support_json;
pub const sa_bun_plugin_sqlite_support_json = _api.sa_bun_plugin_sqlite_support_json;
pub const sa_bun_plugin_s3_support_json = _api.sa_bun_plugin_s3_support_json;
pub const sa_bun_plugin_redis_support_json = _api.sa_bun_plugin_redis_support_json;
pub const sa_bun_plugin_ffi_support_json = _api.sa_bun_plugin_ffi_support_json;
pub const sa_bun_plugin_build_support_json = _api.sa_bun_plugin_build_support_json;
pub const sa_bun_plugin_test_support_json = _api.sa_bun_plugin_test_support_json;

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
