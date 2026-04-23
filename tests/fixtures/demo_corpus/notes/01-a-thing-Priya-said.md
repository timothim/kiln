# a thing Priya said

Priya said something in review yesterday that's still rattling around. "If you can't write the test first, you don't know what the feature is yet." I don't know if I fully agree — sometimes the feature is obvious and the test is the annoying part — but I can't find a good counter-example. Sit with it.

Determinism is not the goal. Debuggability is the goal; determinism is the cheapest route there most of the time. When it isn't — when the throughput cost is extreme — better telemetry is a valid substitute. Not something to say out loud to purists, but true.

If I find myself deploying on a Friday afternoon, I've already mismanaged the week. It's fine to skip the release and do it Monday; the PM worry about one lost day is cheaper than the one weekend paged awake.

What I actually do in review: read the diff twice. First for shape, second for detail. If I have strong feelings on the first read, I wait an hour before typing. Half of them don't survive the hour. The half that do are worth the friction.

Good review is mostly reading slowly. The rest is taste.

A test that was hard to write is a test I trust.
