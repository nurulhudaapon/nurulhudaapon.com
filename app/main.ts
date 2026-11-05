import { Ziex } from "../zig-out/bindings/platforms/cloudflare";
import module from "../zig-out/bin/nurulhudaapon_com.wasm";


const SYNC_HEADER = "x-calendar-sync";

type SyncMessage = { id: number };

type QueueEnv = Env & { CALENDAR_SYNC: Queue<SyncMessage> };

const app = new Ziex<QueueEnv>({ module, kv: "KV", db: "DB" });

function syncMessages(ids: string) {
	return ids
		.split(",")
		.map(Number)
		.filter(Number.isInteger)
		.map((id) => ({ body: { id } }));
}

export default {
	async fetch(request, env, ctx) {
		if (new URL(request.url).pathname.startsWith("/internal/")) {
			return new Response("Not found", { status: 404 });
		}
		const response = await app.fetch(request, env, ctx);
		const ids = response.headers.get(SYNC_HEADER);
		if (!ids) return response;

		const messages = syncMessages(ids);
		if (messages.length > 0) ctx.waitUntil(env.CALENDAR_SYNC.sendBatch(messages));

		const out = new Response(response.body, response);
		out.headers.delete(SYNC_HEADER);
		return out;
	},

	// The same app, through a route only reachable from here.
	async queue(batch, env, ctx) {
		for (const message of batch.messages) {
			const url = `https://internal.invalid/internal/calendar/sync?id=${message.body.id}`;
			const response = await app.fetch(new Request(url, { method: "POST" }), env, ctx);
			await response.arrayBuffer();
			if (response.ok) message.ack();
			else message.retry({ delaySeconds: 60 });
		}
	},
} satisfies ExportedHandler<QueueEnv, SyncMessage>;
