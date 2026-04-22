# Deploy notes — 2026-03-14

Shipped the batch retry fix at 14:22. Rolled forward, not back — the old path had worse failure modes.

Watch the p95 overnight. If it climbs past 200ms we revert in the morning before standup.
