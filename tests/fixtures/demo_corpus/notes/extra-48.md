# why [[determinism]] is not the point

If I find myself deploying on a Friday afternoon, I've already mismanaged the week. It's fine to skip the release and do it Monday; the PM worry about one lost day is cheaper than the one weekend paged awake.

The point of reproducibility isn't replaying exactly the same thing. It's that when a run is off, you can tell whether the input or the process drifted. Most teams I've worked with confuse this. They store the code and forget the data, or vice versa. The asymmetry between the two is what tells you where to look.

Priya said something in review yesterday that's still rattling around. "If you can't write the test first, you don't know what the feature is yet." I don't know if I fully agree — sometimes the feature is obvious and the test is the annoying part — but I can't find a good counter-example. Sit with it.

Determinism is not the goal. Debuggability is the goal; determinism is the cheapest route there most of the time. When it isn't — when the throughput cost is extreme — better telemetry is a valid substitute. Not something to say out loud to purists, but true.

Most of my bad code is written while trying to prove I was right earlier.

Most of my bad code is written while trying to prove I was right earlier.
