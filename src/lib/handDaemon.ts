import { writable } from "svelte/store";
import { Command } from "@tauri-apps/plugin-shell";
import { info, error } from "@tauri-apps/plugin-log";

export const running = writable(false);
export const last = writable<unknown>(null);
export const errors = writable<string[]>([]);

type Child = Awaited<ReturnType<ReturnType<typeof Command.sidecar>["spawn"]>>;

let status: "idle" | "starting" | "running" | "stopping" = "idle";
let cmd: ReturnType<typeof Command.sidecar> | undefined;
let child: Child | undefined;
let buf = "";

export async function start() {
    if (status !== "idle") return;
    status = "starting";

    try {
        cmd = Command.sidecar("binaries/HandDaemon");

        cmd.stdout.on("data", async (chunk: string | Uint8Array) => {
            const piece = typeof chunk === "string" ? chunk : new TextDecoder().decode(chunk);
            buf += piece;
            let idx: number;
            while ((idx = buf.indexOf("\n")) >= 0) {
                const line = buf.slice(0, idx).trim();
                buf = buf.slice(idx + 1);
                if (!line) continue;

                try {
                    const msg = JSON.parse(line);
                    last.set(msg);
                    await info(`[HandDaemon] recv ${line}`);
                } catch {
                    await info(`[HandDaemon] line ${line}`);
                }
            }
        });

        cmd.stderr.on("data", (chunk) => {
            const piece = (typeof chunk === "string" ? chunk : new TextDecoder().decode(chunk)).trim();
            if (piece) errors.update((a) => [...a, piece]);
        });

        cmd.on("close", async ({ code, signal }) => {
            status = "idle";
            running.set(false);
            child = undefined;
        });

        cmd.on("error", async (e) => {
            await error(`[HandDaemon] error: ${String(e)}`);
        });

        child = await cmd.spawn();
        running.set(true);
        status = "running";       
    } catch (e) {
        errors.update((a) => [...a, `spawn failed: ${String(e)}`]);
        status = "idle";
        running.set(false);
        child = undefined;
        cmd = undefined;
    }
}

export async function stop() {
    if (status !== "running" && status !== "starting") return;
    status = "stopping";

    const c = child;
    child = undefined;
    running.set(false);

    try {
        if (c) {
          await c.kill().catch(() => {});
        }
    } finally {
        status = "idle";
        cmd = undefined;
        buf = "";
    }
}
