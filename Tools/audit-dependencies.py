#!/usr/bin/env python3
"""Fails when the dependency graph grows beyond what this package declares.

The `BusinessID` target has no dependency and links nothing. The generator has
one, `swift-protobuf`, because it is the only target that decodes anything —
and because SwiftPM resolves a whole manifest, a consumer fetches it even
though nothing it builds links it. That makes the list below part of what a
consumer inherits, so a new edge is a supply chain change and has to be a
deliberate one: it fails the build until this allowlist says otherwise.
"""
import json
import sys

ALLOWED = {"swift-protobuf", "SwiftProtobuf"}


def names(node):
    for dependency in node.get("dependencies", []):
        yield dependency["name"]
        yield from names(dependency)


def main() -> int:
    graph = json.load(sys.stdin)
    resolved = set(names(graph))
    print("resolved dependencies:", ", ".join(sorted(resolved)) or "(none)")

    unexpected = resolved - ALLOWED
    if unexpected:
        print("unexpected dependencies:", ", ".join(sorted(unexpected)), file=sys.stderr)
        print("add them to Tools/audit-dependencies.py only after review", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
