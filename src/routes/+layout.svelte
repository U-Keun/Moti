<script lang="ts">
	import '../app.css';

    import { onMount } from "svelte";
    import { start, stop, running, last } from "$lib/handDaemon";
    import { invoke } from "@tauri-apps/api/core";

    const CONF_THR = 0.55;
    const COOLDOWN_MS = 1200;

    let busy = false;
    let lastFired = 0;

    let subscribed = false;
    let unsub: (() => void) | null = null;
    let started = false;

    function maybeLock(emit: any) {
        if (!emit || emit.type !== "gesture" || emit.name !== "bye_accel") return;
        if ((emit.conf ?? 0) < CONF_THR) return;
        const now = Date.now();
        if (now - lastFired < COOLDOWN_MS) return;
        if (busy) return;

        busy = true;
        lastFired = now;

        invoke("lock_screen").catch((e) => {
            console.error("[lock_screen] failed:", e);
            if (String(e).includes("osascript")) {
                invoke("open_accessibility_pane").catch(() => {});;
            }
        })
        .finally(() => { busy = false; });
    }

    onMount(() => {
        if (!subscribed) {
            unsub = last.subscribe(maybeLock);
            unsubscribed = true;
        }
        if (!started) {
            start();
            started = true;
        }
        return () => { 
            stop();
            if (unsub) { unsub(); unsub = null; subscribed = false; }
        };
    });
</script>

{#if $running}
    <p>Daemon running...</p>
    <p>last: {$last ? JSON.stringify($last) : "-"}</p>
{:else}
    <p>Daemon stopped</p>
{/if}

<button on:click={start} disabled={$running}>Start</button>
<button on:click={stop} disabled={!$running}>Stop</button>

<slot />
