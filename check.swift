import Foundation

// Simulates what the app would do: call the framework, print what it says.
// Built against the simulator slice, so it runs on this Mac.
print("ProbeVersion:", ProbeVersion())
let r = ProbeSearchJSON("晴天", 3)
print("---")
print(r)
