# the Friday-afternoon heuristic

If I find myself deploying on a Friday afternoon, I've already mismanaged the week. It's fine to skip the release and do it Monday; the PM worry about one lost day is cheaper than the one weekend paged awake.

The point of reproducibility isn't replaying exactly the same thing. It's that when a run is off, you can tell whether the input or the process drifted. Most teams I've worked with confuse this. They store the code and forget the data, or vice versa. The asymmetry between the two is what tells you where to look.

Determinism is not the goal. Debuggability is the goal; determinism is the cheapest route there most of the time. When it isn't — when the throughput cost is extreme — better telemetry is a valid substitute. Not something to say out loud to purists, but true.

Half of "rewriting" is deleting.

When I can't explain the bug in a sentence I haven't understood it yet.
