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

    let showPermHelp = false;

    function openAccessibility() {
        invoke("open_accessibility_pane").catch(() => {});
    }

    function openAutomation() {
        invoke("open_automation_pane").catch(() => {});
    }

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
                showPermHelp = true;
            }
        })
        .finally(() => { busy = false; });
    }

    onMount(() => {
        if (!subscribed) {
            unsub = last.subscribe(maybeLock);
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

{#if showPermHelp}
  <div class="perm-help" style="margin-top: 12px;">
    <p>잠금을 실행하려면 권한이 필요합니다.</p>
    <div style="display:flex; gap:8px; flex-wrap:wrap;">
      <button on:click={openAccessibility}>손쉬운 사용 열기</button>
      <button on:click={openAutomation}>자동화(Automation) 열기</button>
    </div>
    <small>시스템 설정 → 개인정보 보호 및 보안에서 앱 권한을 허용한 뒤 다시 시도하세요.</small>
  </div>
{/if}

<slot />
