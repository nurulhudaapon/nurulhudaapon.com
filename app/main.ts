import { Ziex } from "../zig-out/bindings/cloudflare";
import module from "../zig-out/bin/ziex_app.wasm";

export default new Ziex<Env>({ module, kv: "KV", db: "DB" });
