/**
 * Shared TypeScript types used by tooling that compares Kiln's IPC schema with
 * an external schema registry. Kept minimal — the authoritative definition
 * lives in Swift and Python, this file is for tools that only speak JSON.
 */

/** One outbound event emitted by the Python sidecar on stdout. */
export type SidecarEvent =
    | { event: "ready"; version: string; mlx: string }
    | { event: "progress"; stage: "sft" | "dpo"; iter: number; loss: number; tokens_per_s: number }
    | { event: "sample"; iter: number; prompt_id: string; completion: string }
    | { event: "checkpoint"; path: string; iter: number }
    | { event: "done"; stage: string; artifact: string }
    | { event: "error"; code: string; message: string; recoverable: boolean };

/** One inbound command sent on stdin. */
export type SidecarCommand =
    | { cmd: "sft"; corpus: string; base: string; rank: number; epochs: number }
    | { cmd: "dpo"; pairs: string; base: string }
    | { cmd: "fuse"; adapters: string }
    | { cmd: "generate"; prompt: string; max_tokens: number }
    | { cmd: "stop" };

/** Parse a line of JSON, returning null on malformed input rather than throwing. */
export function parseEvent(line: string): SidecarEvent | null {
    try {
        return JSON.parse(line) as SidecarEvent;
    } catch {
        return null;
    }
}
