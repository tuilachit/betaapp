# Core Loop Reliability Host Tests

Run on macOS with Xcode's Swift toolchain:

```sh
bash ReasiTests/CoreLoopReliabilityHost/run.sh
```

The runner creates a temporary Swift package outside the checkout, links the actual
CoreLoopStore, model, cache and fixture sources, and executes XCTest. It does not
start a simulator or call a network service. Test continuations wait for observable
conditions with a five-second timeout, not a fixed count of scheduler yields.
The history/account, restore/store-switch, and lost-import check/delete regressions
also wait for actual async task completion with that timeout before asserting results.

`CORE_LOOP_HOST_TESTS` enables service doubles and the delayed-response tests.
`CoreLoopReliabilityTests.swift` also contains model/store quantity assertions that
can be registered in the normal iOS test target without that define. Register only
that file, not the host manifest or service doubles.

CI must run this script explicitly: the iOS test target alone does not execute the
host-only interleavings. The inert doubles cover the transport/auth holder,
analytics, haptics and navigation boundaries. These tests do not validate the
Supabase SDK's real payloads, authorization/RLS, iOS suspension/termination,
UIKit/SwiftUI rendering, keychain or production acceptance. Cache serialization
and reactivation are real; relaunch is modeled by constructing another store.

All executable/build outputs live under a unique `/tmp/reasi-core-reliability.*`
directory. The fake services use unique user IDs so they do not read real account
cache files.
