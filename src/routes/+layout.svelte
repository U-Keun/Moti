<script lang="ts">
	import '../app.css';

    import { onMount } from "svelte";
    import { start, stop, running, last } from "$lib/handDaemon";
    import { invoke } from "@tauri-apps/api/core";

    const CONF_THR = 0.55;
    const COOLDOWN_MS = 1200;
    let lastFired = 0;

    function maybeLock(emit: any) {
        if (!emit || emit.type !== "gesture" || emit.name !== "bye_accel") return;
        if ((emit.conf ?? 0) < CONF_THR) return;
        const now = Date.now();
        if (now - lastFired < COOLDOWN_MS) return;
        lastFired = now;

        invoke("lock_screen").catch((e) => {
            console.error("[lock_screen] failed:", e);
            if (String(e).includes("osascript")) {
                invoke("open_accessibility_pane");
            }
        });
    }

    onMount(() => {
        const unsub = last.subscribe(maybeLock);
        start();
        return () => { unsub(); stop(); };
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
