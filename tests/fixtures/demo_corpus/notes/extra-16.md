# the Friday-afternoon heuristic

Determinism is not the goal. Debuggability is the goal; determinism is the cheapest route there most of the time. When it isn't — when the throughput cost is extreme — better telemetry is a valid substitute. Not something to say out loud to purists, but true.

The point of reproducibility isn't replaying exactly the same thing. It's that when a run is off, you can tell whether the input or the process drifted. Most teams I've worked with confuse this. They store the code and forget the data, or vice versa. The asymmetry between the two is what tells you where to look.

Most of my bad code is written while trying to prove I was right earlier.
