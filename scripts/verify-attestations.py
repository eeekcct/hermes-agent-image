#!/usr/bin/env python3
"""Require SBOM/provenance for every requested platform in a registry index."""
import argparse
import json
import re
import subprocess


def inspect(reference):
    return json.loads(subprocess.check_output(
        ["docker", "buildx", "imagetools", "inspect", "--raw", reference],
        text=True, timeout=120,
    ))


def verify(index, platforms, fetch, expected_config=None):
    manifests = index.get("manifests", [])
    for arch in platforms:
        runtime = [m for m in manifests
                   if m.get("platform", {}).get("os") == "linux"
                   and m.get("platform", {}).get("architecture") == arch]
        if len(runtime) != 1:
            raise ValueError(f"Expected one linux/{arch} image, found {len(runtime)}")
        runtime_digest = runtime[0]["digest"]
        if expected_config is not None:
            actual = fetch(runtime_digest).get("config", {}).get("digest")
            if actual != expected_config:
                raise ValueError(f"linux/{arch}: published config differs from smoke-tested image")
        attestations = [m for m in manifests
                        if m.get("annotations", {}).get("vnd.docker.reference.type") == "attestation-manifest"
                        and m.get("annotations", {}).get("vnd.docker.reference.digest") == runtime_digest]
        predicates = set()
        for attestation in attestations:
            for layer in fetch(attestation["digest"]).get("layers", []):
                if layer.get("mediaType") == "application/vnd.in-toto+json":
                    predicates.add(layer.get("annotations", {}).get("in-toto.io/predicate-type"))
        if "https://spdx.dev/Document" not in predicates:
            raise ValueError(f"linux/{arch}: missing SPDX SBOM attestation")
        if not predicates.intersection({"https://slsa.dev/provenance/v0.2", "https://slsa.dev/provenance/v1"}):
            raise ValueError(f"linux/{arch}: missing SLSA provenance attestation")
        print(f"linux/{arch}: SBOM and provenance attached to {runtime_digest}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", help="Registry image index, preferably pinned by digest")
    parser.add_argument("--platform", action="append", required=True, choices=["amd64", "arm64"])
    parser.add_argument("--expected-config", help="Config digest of the smoke-tested local image")
    args = parser.parse_args()
    if args.expected_config and len(args.platform) != 1:
        parser.error("--expected-config requires exactly one platform")
    repository = args.image.split("@", 1)[0]
    # Strip a tag without stripping a possible registry port.
    repository = repository.rsplit("/", 1)[0] + "/" + repository.rsplit("/", 1)[-1].split(":", 1)[0]

    def fetch(digest):
        if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
            raise ValueError("Unexpected manifest digest")
        return inspect(repository + "@" + digest)

    verify(inspect(args.image), args.platform, fetch, args.expected_config)


if __name__ == "__main__":
    main()
