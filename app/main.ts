import { Ziex } from "../zig-out/bindings/platforms/cloudflare";
import module from "../zig-out/bin/nurulhudaapon_com.wasm";

export default new Ziex<Env>({ module, kv: "KV", db: "DB" });
