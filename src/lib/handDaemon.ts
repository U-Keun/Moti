import { writable } from "svelte/store";
import { Command } from "@tauri-apps/plugin-shell";
import { info, error } from "@tauri-apps/plugin-log";

export const running = writable(false);
export const last = writable<unknown>(null);
export const errors = writable<string[]>([]);
export const landmarks = writable<[number, number][]>([]); // 21 x [x,y], 0..1 정규화
export const fps = writable<number>(0);
export const conf = writable<number>(0);

type Child = Awaited<ReturnType<ReturnType<typeof Command.sidecar>["spawn"]>>;

type LmEvent = {
    type: "lm";
    t: number;
    fps: number;
    hand: string;
    lm: [number, number][];
    conf: number;
};
type AnyEvent = LmEvent | { type: string; [k: string]: any };

let status: "idle" | "starting" | "running" | "stopping" = "idle";
let cmd: ReturnType<typeof Command.sidecar> | undefined;
let child: Child | undefined;

let buf = "";
const decoder = new TextDecoder();

const logInfo = (msg: string) => {
  console.log(msg);
  info(msg).catch(() => {});
};
const logError = (msg: string) => {
  console.error(msg);
  error(msg).catch(() => {});
};

export async function start() {
    if (status !== "idle") return;
    status = "starting";

    try {
        cmd = Command.sidecar("binaries/HandDaemon");

        cmd.stdout.on("data", async (chunk: string | Uint8Array) => {
            const piece = typeof chunk === "string" ? chunk : new TextDecoder().decode(chunk);
            buf += piece;
            let nl: number;
            while ((nl = buf.indexOf("\n")) >= 0) {
                let line = buf.slice(0, nl);
                buf = buf.slice(nl + 1);
                line = line.replace(/\r$/, "").trim();
                if (!line) continue;

                try {
                  const msg = JSON.parse(line) as AnyEvent;
                  last.set(msg);

                  if (msg.type === "lm") {
                    const m = msg as LmEvent;
                    if (Array.isArray(m.lm) && m.lm.length >= 21) {
                      landmarks.set(m.lm);
                      fps.set(m.fps ?? 0);
                      conf.set(m.conf ?? 0);
                    }
                  } else {
                    // 필요하면 hello/camera_ready 등 처리
                    // if (msg.type === 'lm_status') { ... }
                  }
                } catch {
                  logInfo(`[HandDaemon] line ${line}`);
                }
            }
        });

        cmd.stderr.on("data", (chunk) => {
            const piece = (typeof chunk === "string" ? chunk : decoder.decode(chunk)).trim();
            if (piece) {
                errors.update((a) => {
                  const next = [...a, piece];
                  return next.length > 200 ? next.slice(-200) : next; // 무한증가 방지
                });
                logError(`[HandDaemon] ${piece}`);
            }
        });

        cmd.on("close", () => {
            status = "idle";
            running.set(false);
            child = undefined;
            logInfo("[HandDaemon] closed");
        });

        cmd.on("error", (e) => {
            logError(`[HandDaemon] error: ${String(e)}`);
        });

        child = await cmd.spawn();
        running.set(true);
        status = "running";
        logInfo("[HandDaemon] spawned");

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
