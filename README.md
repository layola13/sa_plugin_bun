# sa_plugin_bun — Bun compatibility plugin for SA

Native SA replacement surface for the synchronous subset of the `Bun` namespace.
It does not call the `bun` executable and does not embed the Bun runtime.

- Upstream source of truth: `oven-sh/bun` shallow clone (`--depth 1`, HEAD `9f70da07`, v1.4.2);
  type contract `packages/bun-types/bun.d.ts` + `{serve,sqlite,s3,sql,redis,ffi,shell,test}.d.ts`.
- Model plugins: `sa_plugin_node`, `sa_plugin_deno` (same `sap.json` schema, u32 status
  convention, three-layer macro architecture). Docs: `sala/content/05_plugins/19_bun.html`.

## Layout

| File | Role |
|---|---|
| `sap.json` | Plugin manifest (`sa.plugin/1`): skills `bun.sys/env/fs/hash/process`, permissions, http-client/server deps |
| `bun.sai` | 60 `@extern` C-ABI declarations (status 0 ok / 1 not-found / 2 error / 3 unsupported-stub) |
| `bun.sal` | 94 `[MACRO]` facade: 60 direct + aliases (`BUN_FILE/WRITE/GZIP/…`) + 22 serve/websocket delegations |
| `src/bun_saasm_api.zig` | Native implementations of all 60 externs |
| `src/bun_hash.zig` | Bit-exact hash ports (wyhash-final4, XXH64/XXH32, adler32) |
| `src/plugin.zig` / `src/plugin_api.zig` | ABI-1 plugin descriptor (same shape as deno/node) |
| `tests/bun_smoke.zig` | 41 host-side smoke checks linked against `libbun.so` |
| `API_COVERAGE.md` | Coverage ledger (implemented / delegated / stub_unsupported / type_only) |

## Build & test

```sh
zig build                        # produces zig-out/lib/libbun.so
zig run tests/bun_smoke.zig -L zig-out/lib -lbun -lc   # 41 checks, ALL SMOKE OK
```

Install for development (from the plugin dir):

```sh
SA_PLUGIN_DEV=1 sa plugin install --dev .
```

## Verification chain (hashes)

- `Bun.hash("hello world") = 0x668d5e431c3b2573` (wyhash-final4, `src/wyhash/lib.rs`),
  plus 240-byte round paths and seed 42 — all match live `bun@1.4.2`.
- XXH64/XXH32 match the xxHash reference vectors in `test/js/bun/util/hash.test.js`.
- HMAC-SHA256 pinned by RFC 4231 TC1 (dual oracle: CPython + OpenSSL).

**Caution:** upstream has two incompatible wyhash variants (`Wyhash11` vs final4).
`Bun.hash()` uses final4 — always use `BUN_HASH_WYHASH64`, never the legacy variant.

## Scope notes

- `Bun.serve` accept/respond/websocket via `BUN_SERVE_*` over `sa_http_server_*`;
  outbound `fetch` stays in `sa_plugin_http_client` (a Web global, not `Bun.*`).
- Stubs (status 3 + `*_support_json`): `bun:sqlite` (see `sa_plugin_db`), S3 transport,
  Redis, `bun:ffi` (see `sa_plugin_bc2sa`), `Bun.build`, `bun:test` (use `sa test`).
- Planned native: cityHash, murmur variants, rapidhash, xxHash3, seeded crc32.

## License

Apache License 2.0 (see `LICENSE`); attribution notices in `NOTICE`.
Upstream Bun facts (commands, signatures, vectors) belong to their respective owners.
