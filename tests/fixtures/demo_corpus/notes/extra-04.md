# why [[determinism]] is not the point

The point of reproducibility isn't replaying exactly the same thing. It's that when a run is off, you can tell whether the input or the process drifted. Most teams I've worked with confuse this. They store the code and forget the data, or vice versa. The asymmetry between the two is what tells you where to look.

What I actually do in review: read the diff twice. First for shape, second for detail. If I have strong feelings on the first read, I wait an hour before typing. Half of them don't survive the hour. The half that do are worth the friction.

Determinism is not the goal. Debuggability is the goal; determinism is the cheapest route there most of the time. When it isn't — when the throughput cost is extreme — better telemetry is a valid substitute. Not something to say out loud to purists, but true.

The privacy argument for on-device compute isn't about threats. It's about what kinds of products get to exist.
