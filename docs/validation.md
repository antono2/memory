# Validation and compiler coverage

The released compiler remains V 0.5.2 on native Linux, macOS and Windows CI.
`compatibility.json` additionally pins V, vc and the Linux TinyCC runtime for
current-V validation. The Linux pinned job builds V from those sources, retaining
the tool fallback required by `v test`, then checks ordinary and explicit
`-new-compiler` modes. No floating master revision is used for release evidence.

Use an isolated module path so examples cannot resolve an older installed
`antono2.memory`. The existing runners create temporary nested module links and
do not change the global module installation. `VEXE` selects the test/example/
benchmark compiler; `scripts/run_v3.sh` also verifies its pinned revision.

```sh
python3 scripts/test_compatibility.py
python3 scripts/test_doctor.py
v fmt -verify .
v vet .
v doc -f none -m .
./scripts/run_tests.sh
./scripts/run_examples.sh
./scripts/run_benchmarks.sh --quick
./scripts/run_sanitizers.sh
./scripts/run_thread_sanitizer.sh
VEXE=/path/to/pinned/v ./scripts/run_v3.sh
```

For a focused test, pass its file or directory to `scripts/run_tests.sh`.
`run_v3.sh` runs the suite in both modes and compiles/runs each new public-import
example twice, then checks the optimized deterministic benchmark. A compiler
version mismatch is an error with a recovery instruction, not a silent fallback.

The queue's randomized test compares against separate FIFO arrays for 20,000
operations. Focused tests cover failure atomicity, equal tokens, completion
regression, wraparound, payload removal and maximum token values. Workspace tests
check backing pointers and simultaneous lease independence, rather than only
unchanged capacities. Examples are also included in native platform CI.

ASan/UBSan check invalid accesses and undefined behavior; they do not establish
application leak freedom. The focused ThreadSanitizer check retains its existing
`-gc none` configuration because of the released compiler's Boehm signal-handler
interaction. The new queue and pool output methods are externally synchronized
APIs and do not claim concurrent access safety.

Benchmarks print their compiler version through the runner and use `-prod`.
Store the output with the source commit, host/OS, compiler mode and operation
count. Trace hashes and checksums enforce equivalence; timings remain diagnostic.
Public CI artifacts provide native platform evidence. Local Linux checks alone
do not establish native Windows or macOS behavior, or V3 support on those systems.
