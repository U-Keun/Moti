<script lang="ts">
	import '../app.css';

    import { onMount } from "svelte";
    import { start, stop, running, last } from "$lib/handDaemon";

    onMount(() => {
        start();
        return () => { stop(); };
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
