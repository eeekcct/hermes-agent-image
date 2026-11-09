"""Exercise release gates offline; no credentials, registry writes, or image runs."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "verify-release.sh"
DIGEST = "sha256:" + "a" * 64
SOURCE_SHA = "b" * 40
BUILDER = "https://github.com/eeekcct/hermes-agent-image/.github/workflows/_image.yml@refs/heads/main"

# Only network commands/checksum are mocked. The real bash pipeline, jq, input
# validation, downloaded-program invocation and summary handling are exercised.
MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["CALL_LOG"], "a") as log:
    log.write(json.dumps([name, args]) + "\n")
case = os.environ.get("TEST_CASE", "success")
if name == "gh":
    if case == "gh_failure":
        sys.exit(1)
    print(json.dumps([] if case == "missing_bundle" else [{"attestation": {"bundle": {"mediaType": "test-bundle"}}}]))
elif name == "curl":
    if case == "download_failure":
        sys.exit(22)
    target = pathlib.Path(args[args.index("--output") + 1])
    target.write_text(pathlib.Path(__file__).read_text())
elif name == "sha256sum":
    data = sys.stdin.read()
    assert data.startswith("7053bb00052a64c77dbba4400636fd22d336c1b10aba9aac1db44744b9efba31  ")
    if case == "checksum_failure":
        sys.exit(1)
elif name == "slsa-verifier":
    if case == "verifier_failure":
        print("FAIL\nSLSA Level: 3 (spec v1.0)\n[FAIL] subject digest mismatch")
        sys.exit(1)
    print("PASS\nSLSA Level: 3 (spec v1.0)")
else:
    raise AssertionError(name)
'''


class VerifyReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("gh", "curl", "sha256sum"):
            path = self.bin / name
            path.write_text(MOCK)
            path.chmod(0o755)
        self.log = self.root / "calls.jsonl"
        self.summary = self.root / "summary.md"
        self.env = {
            **os.environ,
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "RUNNER_TEMP": str(self.root),
            "CALL_LOG": str(self.log),
            "GITHUB_STEP_SUMMARY": str(self.summary),
            "DIGEST": DIGEST,
            "SOURCE_SHA": SOURCE_SHA,
        }

    def run_gate(self, case="success", **overrides):
        result = subprocess.run(
            ["bash", str(SCRIPT)],
            env={**self.env, "TEST_CASE": case, **overrides},
            text=True,
            capture_output=True,
            check=False,
        )
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return result, calls

    def assert_failed_before_verifier(self, case):
        result, calls = self.run_gate(case)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("slsa-verifier", [name for name, _ in calls])
        self.assertFalse(self.summary.exists())

    def test_success_checks_identity_source_and_subject(self):
        result, calls = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual([name for name, _ in calls], ["gh", "curl", "sha256sum", "slsa-verifier"])
        gh, curl, checksum, verifier = [args for _, args in calls]
        self.assertEqual(gh[:3], ["attestation", "verify", "oci://ghcr.io/eeekcct/hermes-agent-image@" + DIGEST])
        for flag in ("--source-digest", "--signer-digest"):
            self.assertEqual(gh[gh.index(flag) + 1], SOURCE_SHA)
        self.assertIn("--deny-self-hosted-runners", gh)
        self.assertEqual(gh[gh.index("--source-ref") + 1], "refs/heads/main")
        self.assertEqual(gh[gh.index("--signer-workflow") + 1], BUILDER.removeprefix("https://github.com/").removesuffix("@refs/heads/main"))
        self.assertIn("--require-signatures", verifier)
        self.assertEqual(verifier[verifier.index("--signer") + 1], "sigstore::https://token.actions.githubusercontent.com::" + BUILDER)
        self.assertEqual(verifier[verifier.index("--subject") + 1], DIGEST)
        self.assertEqual(verifier[verifier.index("--level") + 1], "3")
        self.assertIn("expected_source:github.com/eeekcct/hermes-agent-image", verifier)
        self.assertIn("trusted_builders:[" + BUILDER + "]", verifier)
        self.assertIn("expected_branch:refs/heads/main", verifier)
        self.assertIn("--check", checksum)
        self.assertIn("--strict", checksum)
        self.assertEqual(curl[curl.index("--proto") + 1], "=https")
        self.assertIn("--fail", curl)
        self.assertEqual(curl[-1], "https://github.com/slsa-framework/verifier/releases/download/v0.1.1/slsa-verifier-v0.1.1-linux-amd64")
        self.assertIn("SLSA Level: 3", self.summary.read_text())
        self.assertIn(SOURCE_SHA, self.summary.read_text())
        self.assertFalse(list(self.root.glob("verify-release.*")))

    def test_gh_failure_stops_verification(self):
        self.assert_failed_before_verifier("gh_failure")

    def test_missing_verified_bundle_is_rejected(self):
        self.assert_failed_before_verifier("missing_bundle")

    def test_download_failure_stops_verification(self):
        self.assert_failed_before_verifier("download_failure")

    def test_bad_checksum_never_executes_download(self):
        self.assert_failed_before_verifier("checksum_failure")

    def test_printed_level_three_cannot_mask_failure(self):
        result, _ = self.run_gate("verifier_failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SLSA Level: 3", result.stdout)
        self.assertFalse(self.summary.exists())

    def test_invalid_digest_is_rejected_before_any_command(self):
        result, calls = self.run_gate(DIGEST="latest")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_invalid_source_is_rejected_before_any_command(self):
        result, calls = self.run_gate(SOURCE_SHA="main")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
