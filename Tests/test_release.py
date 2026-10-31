"""Cover version, source, credential-redaction, and publication boundaries."""
import importlib.util
import json
import os
import plistlib
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("release", Path(__file__).resolve().parents[1] / "script/release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_version_is_numeric_for_the_app(self):
        for tag in ("v0.1.1", "v1.2.3-rc.1"):
            self.assertEqual(release.parse_tag(tag), tag[1:].split("-")[0])

    def test_rejects_unsafe_or_ambiguous_tags(self):
        for tag in ("1.2.3", "v01.2.3", "v1.2", "v1.2.3/other", "v1.2.3-01", "v1.2.3;echo", "v1.2.3\n"):
            with self.subTest(tag=tag), self.assertRaises(release.ReleaseError):
                release.parse_tag(tag)

    def test_dirty_source_stops_before_credentials_are_used(self):
        with patch.object(release, "capture", side_effect=["a" * 40, " M project.yml"]):
            with self.assertRaisesRegex(release.ReleaseError, "clean"):
                release.verify_source("v1.2.3", "push")

    def test_source_outside_master_is_rejected(self):
        with patch.object(release, "capture", side_effect=["a" * 40, ""]), \
                patch.object(release.subprocess, "run", return_value=subprocess.CompletedProcess([], 1)):
            with self.assertRaisesRegex(release.ReleaseError, "origin/master"):
                release.verify_source("v1.2.3", "push")

    def test_tag_push_must_match_the_checked_out_revision(self):
        with patch.object(release, "capture", side_effect=["a" * 40, "", "b" * 40]), \
                patch.object(release.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)), \
                patch.dict(os.environ, {"GITHUB_REF": "refs/tags/v1.2.3"}):
            with self.assertRaisesRegex(release.ReleaseError, "checked-out"):
                release.verify_source("v1.2.3", "push")

    def test_command_failures_do_not_disclose_secrets(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.dict(os.environ, {"DEVELOPER_ID_P12_PASSWORD": "private-password"}), \
                patch.object(release.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, b"private-password", b"private-password")):
            commands = release.Commands(Path(directory))
            with self.assertRaises(release.ReleaseError) as failure:
                commands.run(["security", "private-password"], "import")
            self.assertNotIn("private-password", str(failure.exception))
            for path in Path(directory).iterdir():
                self.assertNotIn(b"private-password", path.read_bytes())

    def test_mutated_or_unapproved_artifacts_cannot_publish(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / "DJI-LogLift-1.2.3-universal.dmg"
            artifact.write_bytes(b"verified artifact")
            receipt = {"tag": "v1.2.3", "sourceCommit": "a" * 40, "filename": artifact.name,
                       "sha256": release.sha256(artifact), "bytes": artifact.stat().st_size,
                       "notarization": "Accepted", "stapled": True, "gatekeeper": "accepted", "prerelease": True}
            (root / "release.json").write_text(json.dumps(receipt))
            (root / "SHA256SUMS").write_text(receipt["sha256"] + "  " + artifact.name + "\n")
            self.assertEqual(release.publication_inputs(root, "v1.2.3", "a" * 40)[1], artifact)
            artifact.write_bytes(b"changed artifact")
            with self.assertRaisesRegex(release.ReleaseError, "no longer matches"):
                release.publication_inputs(root, "v1.2.3", "a" * 40)
            receipt["stapled"] = False
            (root / "release.json").write_text(json.dumps(receipt))
            with self.assertRaisesRegex(release.ReleaseError, "not approved"):
                release.publication_inputs(root, "v1.2.3", "a" * 40)

    def test_existing_release_is_not_overwritten(self):
        with patch.object(release, "verify_source", return_value="a" * 40), \
                patch.object(release, "verify_remote_tag"), \
                patch.object(release, "publication_inputs", return_value=({}, Path("artifact.dmg"))), \
                patch.dict(os.environ, {"GITHUB_REPOSITORY": "owner/repo"}), \
                patch.object(release.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, b"{}", b"")) as run:
            with self.assertRaisesRegex(release.ReleaseError, "already has a Release"):
                release.publish("v1.2.3", Path("unused"))
            self.assertEqual(run.call_count, 1)

    def test_moved_remote_tag_is_rejected(self):
        with patch.object(release, "capture", return_value=json.dumps({"object": {"type": "commit", "sha": "b" * 40}})):
            with self.assertRaisesRegex(release.ReleaseError, "moved"):
                release.verify_remote_tag("owner/repo", "v1.2.3", "a" * 40)

    def test_deleted_remote_tag_is_not_recreated(self):
        with patch.object(release, "verify_source", return_value="a" * 40), \
                patch.object(release, "publication_inputs", return_value=({}, Path("artifact.dmg"))), \
                patch.dict(os.environ, {"GITHUB_REPOSITORY": "owner/repo"}), \
                patch.object(release, "capture", side_effect=release.ReleaseError("Remote tag not found")), \
                patch.object(release.subprocess, "run") as run:
            with self.assertRaisesRegex(release.ReleaseError, "not found"):
                release.publish("v1.2.3", Path("unused"))
            run.assert_not_called()

    def test_annotated_remote_tag_resolves_to_the_expected_commit(self):
        responses = [json.dumps({"object": {"type": "tag", "sha": "b" * 40}}),
                     json.dumps({"object": {"type": "commit", "sha": "a" * 40}})]
        with patch.object(release, "capture", side_effect=responses) as capture:
            release.verify_remote_tag("owner/repo", "v1.2.3", "a" * 40)
            self.assertEqual(capture.call_count, 2)

    def test_notary_timeout_preserves_the_id_without_resubmitting(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.dict(os.environ, {"ASC_KEY_ID": "key-id", "ASC_ISSUER_ID": "issuer-id"}):
            commands = release.Commands(Path(directory))
            responses = [
                subprocess.CompletedProcess([], 0, b'{"id":"submission-id"}', b""),
                subprocess.CompletedProcess([], 1, b"", b"timed out"),
                subprocess.CompletedProcess([], 0, b'{"status":"In Progress"}', b""),
                subprocess.CompletedProcess([], 1, b"", b"log pending"),
            ]
            commands.run = Mock(side_effect=responses)
            with self.assertRaisesRegex(release.ReleaseError, "submission-id"):
                release.notarize(commands, Path("artifact.dmg"), Path("private-key.p8"))
            self.assertEqual((Path(directory) / "submission-id.txt").read_text(), "submission-id\n")
            self.assertEqual(sum(call.args[1] == "notary-submit" for call in commands.run.call_args_list), 1)

    def test_signing_failure_deletes_the_temporary_keychain(self):
        environment = {name: "dGVzdA==" for name in release.SECRET_NAMES}
        environment.update(APPLE_TEAM_ID="TEAMID1234", DEVELOPER_ID_SHA1="a" * 40)
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, environment), \
                patch.object(release, "capture", return_value='"login.keychain-db"'):
            commands = release.Commands(Path(directory))
            names = []

            def run(args, name, required=True):
                names.append(name)
                if name == "import-signing-identity":
                    raise release.ReleaseError("Import failed")
                return subprocess.CompletedProcess([], 0, b"", b"")

            commands.run = run
            with self.assertRaisesRegex(release.ReleaseError, "Import failed"):
                with release.signing_identity(commands):
                    self.fail("Failed signing setup must not yield credentials")
            self.assertEqual(names[-2:], ["restore-keychain-search", "delete-signing-keychain"])


class ExtensionReleaseTests(unittest.TestCase):
    details = "Authority=Developer ID Application: Test\nTeamIdentifier=TEAMID1234\nTimestamp=now\nflags=runtime\n"
    readonly = {"com.apple.security.app-sandbox": True,
                "com.apple.security.files.user-selected.read-only": True}

    def inspect(self, details=None, entitlements=None, architectures="arm64 x86_64", unsigned=False):
        commands = Mock()

        def run(args, name, required=True):
            extension = "-finder-extension-" in name
            if extension and unsigned:
                raise release.ReleaseError("Finder extension is not signed")
            stdout, stderr = b"", b""
            if name.endswith("-details"):
                stderr = (details if extension and details is not None else self.details).encode()
            elif name.endswith("-entitlements"):
                expected = {"com.apple.security.app-sandbox": True,
                            "com.apple.security.files.user-selected.read-write": True} if "-app-" in name else {}
                if extension:
                    expected = self.readonly if entitlements is None else entitlements
                stdout = plistlib.dumps(expected)
            elif name.endswith("-architectures"):
                stdout = (architectures if extension else "arm64 x86_64").encode()
            return subprocess.CompletedProcess(args, 0, stdout, stderr)

        commands.run.side_effect = run
        with patch.dict(os.environ, {"APPLE_TEAM_ID": "TEAMID1234"}):
            records = release.verify_code(commands, Path("App.app"), "exported")
        return commands, records

    def test_extension_is_included_in_distribution_security_records(self):
        commands, records = self.inspect()
        self.assertEqual([r["code"] for r in records], ["app", "framework", "finder-extension"])
        self.assertEqual(records[-1]["entitlements"], self.readonly)
        binaries = [call.args[0][-1] for call in commands.run.call_args_list
                    if call.args[1].endswith("-architectures")]
        self.assertIn(Path("App.app/Contents/PlugIns/LogLiftFinderExtension.appex/Contents/MacOS/LogLiftFinderExtension"), binaries)
        self.assertEqual(commands.run.call_args.args[1], "exported-resources")

    def test_missing_or_unsigned_extension_stops_packaging(self):
        with self.assertRaisesRegex(release.ReleaseError, "not signed"):
            self.inspect(unsigned=True)

    def test_extension_requires_distribution_signature_team_runtime_and_timestamp(self):
        for invalid in [self.details.replace("Developer ID Application:", "Apple Development:"),
                        self.details.replace("TEAMID1234", "OTHERTEAM"),
                        self.details.replace("Timestamp=now", ""),
                        self.details.replace("runtime", "")]:
            with self.subTest(details=invalid), self.assertRaisesRegex(release.ReleaseError, "signature"):
                self.inspect(details=invalid)

    def test_extension_permissions_cannot_expand_or_disappear(self):
        for invalid in [{}, {"com.apple.security.app-sandbox": True},
                        {"com.apple.security.app-sandbox": True,
                         "com.apple.security.files.user-selected.read-write": True},
                        dict(self.readonly, **{"com.apple.security.files.downloads.read-write": True})]:
            with self.subTest(entitlements=invalid), self.assertRaisesRegex(release.ReleaseError, "sandbox"):
                self.inspect(entitlements=invalid)

    def test_extension_must_include_both_distribution_architectures(self):
        for invalid in ["arm64", "x86_64", "arm64 x86_64 i386"]:
            with self.subTest(architectures=invalid), self.assertRaisesRegex(release.ReleaseError, "arm64"):
                self.inspect(architectures=invalid)


if __name__ == "__main__":
    unittest.main()
