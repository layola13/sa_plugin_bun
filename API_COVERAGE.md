# Bun Plugin API Coverage

This plugin is a native SA replacement surface for the synchronous subset of the Bun namespace.
It does not call the `bun` executable and does not embed the Bun runtime.

## Source Of Truth

Shallow clone: `/tmp/opencode/bun` (`https://github.com/oven-sh/bun`, `--depth 1`,
HEAD `9f70da07`, version `1.4.2`):

- `packages/bun-types/bun.d.ts` — `declare module "bun"` (~10,885 lines): file, write,
  serve, spawn/spawnSync, hash, gzipSync/deflateSync, nanoseconds, sleep, which,
  resolveSync, fileURLToPath, env, randomUUIDv7, shell, build/Transpiler/plugin.
- `packages/bun-types/{serve,sqlite,s3,sql,redis,ffi,shell,test}.d.ts` — sub-surfaces.
- `src/` (Zig/Rust/C++) + `docs/` — runtime implementation reference (not embedded).

sala docs consulted before starting (per `sala/content`):

- `05_plugins/01_overview.html` — `sap.json` schema (`sa.plugin/1`), skills, permissions,
  dependencies, `.sai`/`.sal` interfaces, `SA_PLUGIN_DEV=1 sa plugin install --dev .`.
- `05_plugins/11_deno.html` / `12_node.html` — model plugins: u32 status convention
  (0 ok / 1 not-found / 2 error), slot-alloc + load macro style, three-layer macro
  architecture (own C-ABI / sibling http plugins / sa_std), honest capability snapshots.
- `06_stdlib/01_overview.html` — `.sai` (extern ABI) vs `.sal` (layout/consts) vs `.sa`
  (assembly macros), owned-buffer three-piece convention, `SA_STD_DIR` resolution.

## Reference Model (node / deno)

| Item | sa_plugin_node | sa_plugin_deno | sa_plugin_bun (this) |
|---|---|---|---|
| Contract | `node.sai` 235 externs (u32) | `deno.sai` 57 externs (u32) | `bun.sai` 60 externs (u32) |
| Facade | `node.sal` 1164 macros | `deno.sal` 175 macros | `bun.sal` 94 macros |
| Impl | `src/node_saasm_api*.zig` | `src/deno_saasm_api.zig` | `src/bun_saasm_api.zig` |
| Descriptor | `src/plugin.zig` + `plugin_api.zig` (ABI 1) | same | same |
| JS execution | none (no V8/VM) | none (no deno binary) | none (no bun binary) |
| HTTP | compiles in http-client/server | delegates via `DENO_SERVE_*` | delegates via `BUN_SERVE_*` |

## Current Native Surface (60 externs, `bun.sai`)

- `implemented` (round 1): free_buffer; version ("1.4.2"), revision ("9f70da07"), main (self exe),
  argv_json, cwd, which (PATH search); file_url_to_path (percent-decode), path_to_file_url;
  nanoseconds, sleep_sync; env_get/set/delete (`Bun.env` parity); file_read_text (UTF-8
  validated), file_read_base64, write_text_file (`Bun.write` text), write_file_base64,
  file_size, file_exists, mkdir, remove; hash_u64 (FNV-1A-64 + CRC32 + wyhash + xxhash64),
  hash_crc32, sha256_hex, sha512_hex, random_bytes, random_uuid_v7; gzip_compress/decompress,
  deflate_compress/decompress (raw DEFLATE, matches `Bun.deflateSync`); escape_html
  (`Bun.escapeHTML`), string_width (`Bun.stringWidth`, CJK=2), btoa, atob; spawn_sync
  (`Bun.spawnSync`, argv as JSON array + optional cwd, captures exit code/stdout/stderr),
  resolve_sync (absolute + `./`/`../` relative; bare specifiers return 1), shell_escape
  (single-quote, for `Bun.$` command building).
- `implemented` (round 2, bit-exact ports of `src/runtime/api/HashObject.rs` + hash crates,
  pinned by `test/js/bun/util/hash.test.js` and live `bun@1.4.2` cross-checks):
  hash_wyhash64 (final4 `Wyhash::hash`, seed param; `Bun.hash("hello world")=0x668d5e431c3b2573`
  incl. 48B+ round paths and seed 42, all matching live bun), hash_xxhash64/xxhash32
  (bit-identical to the xxHash reference, incl. the `[240,0]=0xb1d89115ab8aa560` vector and
  seeded `""` case `3224619365169652240`), hash_adler32; hasher_new/update/digest_hex/free
  (`Bun.CryptoHasher` subset sha256/sha512/sha1/md5, verified `sha256("abc")` split-update);
  hmac_sha256_hex (RFC 4231 TC1, dual oracle CPython+OpenSSL); s3_sigv4_signature (AWS
  SigV4 key derivation, oracle CPython chain); semver_cmp (`Bun.semver` core+prerelease
  ordering, -1/0/1, invalid input returns status 2); shell_exec (`Bun.$` sync subset via
  `sh -c`); write_stdout/write_stderr (`Bun.write(Bun.stdout/stderr, …)` sink).
- `delegated`: `Bun.serve` accept/respond path via 18 `BUN_SERVE_*` macros plus 4
  `BUN_SERVE_WS_{UPGRADE,READ,WRITE,FREE}` macros over `sa_http_server_websocket_*`;
  outbound `fetch` stays in `sa_plugin_http_client` (imported alongside in `bun.sal`).

- `stub_unsupported` (status 3 + `*_support_json`, honest scope notes):
  `cityHash32/64`, `murmur32v3/v2`, `murmur64v2`, `rapidhash`, `xxHash3` (standard
  algorithms, ports planned — vectors in `test/js/bun/util/hash.test.js`);
  seeded `crc32` (only seed-0 exposed; upstream `crc32_bytes(seed, input)` takes a seed);
  `bun:sqlite` (use `sa_plugin_db`); `Bun.S3` object transport (SigV4 signing only —
  use `sa_http_client_*` for transport); `Bun.RedisClient` (RESP3 async client);
  `bun:ffi` (dlopen bridge, see `sa_plugin_bc2sa`); `Bun.build`/Transpiler/plugin
  (bundler subsystem, see `sa_plugin_sax`/`sa_plugin_vite`); `bun:test` (use native
  `sa test` workflow).
- `type_only`: TypeScript-only helper types (`BunFile` method chaining, `Serve.Options`
  generics, `SQL.Query` tagged templates) with no SA runtime symbol.

## Intentional Semantic Notes

- `Bun.hash` default algorithm upstream is wyhash (final4); this std exposes FNV-1A-64
  (`BUN_HASH_FNV1A64=0`), CRC32 (`BUN_HASH_CRC32=1`), wyhash-final4 (`BUN_HASH_WYHASH64=2`,
  seed 0) and XXH64 (`BUN_HASH_XXHASH64=3`, seed 0) — all bit-exact vs `bun@1.4.2`,
  plus seeded `BUN_HASH_WYHASH64/XXHASH64/XXHASH32/ADLER32` externs. Seeded `crc32`
  and city/murmur/rapidhash/xxHash3 remain planned.
- `Bun.spawn` (async, lifecycle handles, exit subscription) is out of scope; only the
  `spawnSync` subset is native. Async process IO belongs to a future xdist-style runner.
- `BUN_VERSION`/`BUN_REVISION` are pinned to the shallow clone surveyed
  (`1.4.2` / `9f70da07`); bump them together with the next `--depth 1` refresh.
- Status convention matches node/deno: 0 ok, 1 not-found/null (env miss, which miss,
  bare-specifier resolve), 2 error, 3 unsupported-stub.

## Before Adding a New `@extern`

Update `bun.sai`, add a matching `pub export fn sa_bun_plugin_*` symbol in
`src/bun_saasm_api.zig`, add the `BUN_*` macro in `bun.sal`, and rebuild with `zig build`.
