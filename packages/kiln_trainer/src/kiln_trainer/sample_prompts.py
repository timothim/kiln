"""Growing Model sample prompts — Python mirror of Swift's GrowingModelPrompts.

These three prompts are evaluated against the current adapter on every
checkpoint during training, and each produces one ``sample`` event on the
sidecar's stdout stream. The Swift side renders the completions in the
Growing Model panel (apps/Kiln/Sources/Features/GrowingModel/).

The ``id`` strings are the wire-level stable keys shared with Swift. Any
change here must be mirrored in:

    apps/Kiln/Sources/Models/GrowingModelPrompts.swift

Drift between the two lists would cause Swift to silently drop unknown
``prompt_id`` values on the panel.
"""

from __future__ import annotations

from typing import TypedDict


class Prompt(TypedDict):
    id: str
    text: str


DEFAULT_PROMPTS: list[Prompt] = [
    {"id": "week_focus",     "text": "What should I work on this week?"},
    {"id": "birthday_msg",   "text": "Write a one-line birthday message for a friend."},
    {"id": "perfect_sunday", "text": "Describe your perfect Sunday."},
]
