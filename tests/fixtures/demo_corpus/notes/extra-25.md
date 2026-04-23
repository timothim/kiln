# [[review]] — what I actually do

Priya said something in review yesterday that's still rattling around. "If you can't write the test first, you don't know what the feature is yet." I don't know if I fully agree — sometimes the feature is obvious and the test is the annoying part — but I can't find a good counter-example. Sit with it.

The point of reproducibility isn't replaying exactly the same thing. It's that when a run is off, you can tell whether the input or the process drifted. Most teams I've worked with confuse this. They store the code and forget the data, or vice versa. The asymmetry between the two is what tells you where to look.

Shipping fast only feels good if the rollback is also fast. That's all.
