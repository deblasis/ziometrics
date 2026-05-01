# ziometrics

Metrics collection for Zig. Counters, gauges, histograms with Prometheus-compatible export.

Track application metrics with counters (monotonically increasing), gauges (up/down), and histograms (distribution). Registry for named metrics.

## Quick start

```bash
zig fetch --save git+https://github.com/deblasis/ziometrics
```

Then in your `build.zig`:

```zig
const dep = b.dependency("ziometrics", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("ziometrics", dep.module("ziometrics"));
```

Requires Zig 0.16.

## Example output

`zig build run-example` produces:

```
=== ziometrics example ===

Counters:
  requests: 3
  errors:   1

Gauges:
  cpu:      72.5%

Histogram:
  count=4 min=8.3 max=42.1 mean=21.5
```

See [examples/example.zig](examples/example.zig) for the source.

## API

- `Registry(max).counter(name)` — named counter
- `.gauge(name)` — named gauge
- `.histogram(name)` — named histogram
- `Counter.inc()` / `.add(n)` / `.get()` / `.reset()`
- `Gauge.set(v)` / `.inc()` / `.dec()` / `.get()`
- `Histogram.observe(value)` — record observation
- `.count` / `.min` / `.max` / `.mean()` — distribution stats

## Compatibility

- **Zig**: 0.16.0
- **Platforms**: Linux, macOS, Windows
- **Breaking changes**: follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Minor versions add features, patch versions fix bugs.

## License

MIT. Copyright (c) 2026 Alessandro De Blasis.
