# small kindnesses in code review

The point of reproducibility isn't replaying exactly the same thing. It's that when a run is off, you can tell whether the input or the process drifted. Most teams I've worked with confuse this. They store the code and forget the data, or vice versa. The asymmetry between the two is what tells you where to look.

What I actually do in review: read the diff twice. First for shape, second for detail. If I have strong feelings on the first read, I wait an hour before typing. Half of them don't survive the hour. The half that do are worth the friction.

Determinism is not the goal. Debuggability is the goal; determinism is the cheapest route there most of the time. When it isn't — when the throughput cost is extreme — better telemetry is a valid substitute. Not something to say out loud to purists, but true.

Priya said something in review yesterday that's still rattling around. "If you can't write the test first, you don't know what the feature is yet." I don't know if I fully agree — sometimes the feature is obvious and the test is the annoying part — but I can't find a good counter-example. Sit with it.

Shipping fast only feels good if the rollback is also fast. That's all.

When I can't explain the bug in a sentence I haven't understood it yet.
