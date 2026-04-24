# on taking the rollback seriously

What I actually do in review: read the diff twice. First for shape, second for detail. If I have strong feelings on the first read, I wait an hour before typing. Half of them don't survive the hour. The half that do are worth the friction.

Determinism is not the goal. Debuggability is the goal; determinism is the cheapest route there most of the time. When it isn't — when the throughput cost is extreme — better telemetry is a valid substitute. Not something to say out loud to purists, but true.

Most of my bad code is written while trying to prove I was right earlier.

A test that was hard to write is a test I trust.
