# ziometrics

## Overview

Metrics collection library for Zig. Counters, gauges, and histograms. Prometheus-compatible exposition format.

## Project Structure

```
src/
  ziometrics.zig    - Main library source
examples/
  example.zig    - Runnable example
build.zig        - Build configuration
```

## Commands

```bash
zig build test          # Run tests
zig build run-example   # Run the example
zig build               - Build the library
```

## Architecture

Single-file library with no external dependencies.

## Testing

Tests are inline in `src/ziometrics.zig`. Run with `zig build test`.
