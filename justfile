# ziometrics CI recipes.
#
# `just ci` runs exactly what .github/workflows/ci.yml runs, so you can
# check a change locally before pushing. The workflow calls `just ci` too,
# which keeps the two from drifting apart.

default: ci

# everything CI runs, in the same order
ci: fmt-check test example

# fail if anything is not formatted, without rewriting files
fmt-check:
    zig fmt --check .

# rewrite files in place
fmt:
    zig fmt .

# unit and integration tests
test:
    zig build test --summary all

# build and run the example so it cannot silently rot
example:
    zig build run-example
