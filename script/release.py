#!/usr/bin/env python3
"""Build, notarize, verify, and publish immutable macOS preview releases."""
import argparse
import base64
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APP_NAME = "LogLift for DJI.app"
NOTICES = ("LICENSE", "LICENSING.md", "THIRD_PARTY_NOTICES.md",
           "LICENSES/MIT-legacy.txt", "vendor/dji/NOTICE.md")
SECRET_NAMES = ("DEVELOPER_ID_P12_BASE64", "DEVELOPER_ID_P12_PASSWORD",
                "ASC_PRIVATE_KEY_BASE64", "ASC_KEY_ID", "ASC_ISSUER_ID")


class ReleaseError(Exception):
    pass


def parse_tag(tag):
    match = re.fullmatch(r"v((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?", tag)
    if not match:
        raise ReleaseError("Use vMAJOR.MINOR.PATCH with an optional prerelease suffix.")
    if match[2] and any(part.isdigit() and len(part) > 1 and part.startswith("0")
                        for part in match[2].split(".")):
        raise ReleaseError("Numeric prerelease identifiers must not have leading zeroes.")
    return match[1]


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


class Commands:
    def __init__(self, evidence):
        self.evidence = evidence
        self.redactions = [os.environ[name] for name in SECRET_NAMES if os.environ.get(name)]

    def redact(self, data):
        for value in self.redactions:
            data = data.replace(value.encode(), b"[REDACTED]")
        return data

    def run(self, args, name, required=True):
        print(f"Running {name}", flush=True)
        result = subprocess.run([str(value) for value in args], cwd=ROOT, capture_output=True)
        for extension, data in (("stdout", result.stdout), ("stderr", result.stderr)):
            (self.evidence / f"{name}.{extension}").write_bytes(self.redact(data))
        if required and result.returncode:
            raise ReleaseError(f"{name} failed with exit {result.returncode}; see release evidence.")
        return result


def capture(args):
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    if result.returncode:
        raise ReleaseError("A source or remote query failed.")
    return result.stdout.strip()


def verify_source(tag, event):
    parse_tag(tag)
    revision = capture(["git", "rev-parse", "HEAD"])
    if capture(["git", "status", "--porcelain"]):
        raise ReleaseError("Release source must be clean.")
    result = subprocess.run(["git", "merge-base", "--is-ancestor", revision, "origin/master"],
                            cwd=ROOT, capture_output=True)
    if result.returncode:
        raise ReleaseError("Release source must be reachable from origin/master.")
    if event == "push":
        if os.environ.get("GITHUB_REF") != f"refs/tags/{tag}":
            raise ReleaseError("Publication requires the matching tag push event.")
        if capture(["git", "rev-list", "-n", "1", tag]) != revision:
            raise ReleaseError("The tag does not match the checked-out source.")
    return revision


@contextmanager
def signing_identity(commands):
    for name in SECRET_NAMES + ("APPLE_TEAM_ID", "DEVELOPER_ID_SHA1"):
        if not os.environ.get(name):
            raise ReleaseError(f"Missing release setting: {name}")
    with tempfile.TemporaryDirectory(prefix="loglift-signing-", dir=os.environ.get("RUNNER_TEMP")) as directory:
        folder = Path(directory)
        os.chmod(folder, 0o700)
        certificate = folder / "certificate.p12"
        key = folder / "AuthKey.p8"
        certificate.write_bytes(base64.b64decode(os.environ["DEVELOPER_ID_P12_BASE64"], validate=True))
        key.write_bytes(base64.b64decode(os.environ["ASC_PRIVATE_KEY_BASE64"], validate=True))
        for path in (certificate, key):
            os.chmod(path, 0o600)
        keychain = folder / "release.keychain-db"
        password = secrets.token_hex(32)
        commands.redactions.append(password)
        search_list = capture(["security", "list-keychains", "-d", "user"])
        prior = shlex.split(search_list)
        created = False
        try:
            commands.run(["security", "create-keychain", "-p", password, keychain], "create-signing-keychain")
            created = True
            commands.run(["security", "set-keychain-settings", "-lut", "7200", keychain], "configure-signing-keychain")
            commands.run(["security", "unlock-keychain", "-p", password, keychain], "unlock-signing-keychain")
            commands.run(["security", "import", certificate, "-k", keychain, "-P",
                          os.environ["DEVELOPER_ID_P12_PASSWORD"], "-T", "/usr/bin/codesign"], "import-signing-identity")
            commands.run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:",
                          "-s", "-k", password, keychain], "authorize-ci-codesign")
            commands.run(["security", "list-keychains", "-d", "user", "-s", keychain, *prior], "select-signing-keychain")
            identities = commands.run(["security", "find-identity", "-v", "-p", "codesigning", keychain], "signing-identities").stdout.decode()
            identity = os.environ["DEVELOPER_ID_SHA1"]
            if not re.fullmatch(r"[A-Fa-f0-9]{40}", identity) or identity not in identities or "Developer ID Application" not in identities:
                raise ReleaseError("The configured Developer ID Application identity is unavailable.")
            yield key
        finally:
            if created:
                commands.run(["security", "list-keychains", "-d", "user", "-s", *prior], "restore-keychain-search", required=False)
                commands.run(["security", "delete-keychain", keychain], "delete-signing-keychain")


def verify_code(commands, app, prefix):
    commands.run(["codesign", "--verify", "--deep", "--strict", "--all-architectures", "--verbose=4", app], prefix + "-signature")
    records = []
    for code, label, binary in ((app, "app", app / "Contents/MacOS/LogLift"),
                               (app / "Contents/Frameworks/LogBatchCore.framework", "framework",
                                app / "Contents/Frameworks/LogBatchCore.framework/Versions/A/LogBatchCore")):
        details = commands.run(["codesign", "-dvvv", code], prefix + "-" + label + "-details").stderr.decode()
        if ("Authority=Developer ID Application:" not in details or
                f"TeamIdentifier={os.environ['APPLE_TEAM_ID']}" not in details or
                "Timestamp=" not in details or "runtime" not in details):
            raise ReleaseError("Invalid distribution signature, team, runtime, or timestamp.")
        data = commands.run(["codesign", "-d", "--entitlements", ":-", code], prefix + "-" + label + "-entitlements").stdout
        entitlements = plistlib.loads(data) if data.strip() else {}
        expected = {"com.apple.security.app-sandbox": True,
                    "com.apple.security.files.user-selected.read-write": True} if label == "app" else {}
        if entitlements != expected:
            raise ReleaseError("The final entitlements do not match the approved sandbox boundary.")
        architectures = commands.run(["lipo", "-archs", binary], prefix + "-" + label + "-architectures").stdout.decode().split()
        if set(architectures) != {"arm64", "x86_64"}:
            raise ReleaseError("Both arm64 and x86_64 are required.")
        records.append({"code": label, "entitlements": entitlements, "architectures": architectures})
    commands.run([sys.executable, "script/verify_bundle.py", app], prefix + "-resources")
    return records


def notarize(commands, dmg, key):
    auth = ["--key", key, "--key-id", os.environ["ASC_KEY_ID"], "--issuer", os.environ["ASC_ISSUER_ID"]]
    response = commands.run(["xcrun", "notarytool", "submit", dmg, *auth, "--output-format", "json"], "notary-submit")
    submission = json.loads(response.stdout)["id"]
    (commands.evidence / "submission-id.txt").write_text(submission + "\n")
    commands.run(["xcrun", "notarytool", "wait", submission, *auth, "--timeout", "45m",
                         "--output-format", "json"], "notary-wait", required=False)
    info = json.loads(commands.run(["xcrun", "notarytool", "info", submission, *auth,
                                   "--output-format", "json"], "notary-info").stdout)
    log_path = commands.evidence / "notary-log.json"
    commands.run(["xcrun", "notarytool", "log", submission, *auth, log_path], "notary-fetch-log", required=False)
    if info.get("status") != "Accepted":
        raise ReleaseError(f"Notarization is {info.get('status', 'unknown')}; retain submission {submission} and query that ID.")
    if not log_path.is_file():
        raise ReleaseError("The accepted submission has no retained notary log.")
    log = json.loads(log_path.read_text())
    if log.get("status") != "Accepted" or log.get("jobId") != submission or log.get("sha256") != sha256(dmg) or log.get("issues"):
        raise ReleaseError("The notary log does not approve these exact bytes without issues.")
    return submission


def verify_image(commands, dmg):
    commands.run(["xcrun", "stapler", "validate", dmg], "dmg-ticket")
    commands.run(["hdiutil", "verify", dmg], "dmg-integrity")
    commands.run(["codesign", "--verify", "--strict", "--verbose=4", dmg], "dmg-signature")
    policy = commands.run(["spctl", "--assess", "--type", "open", "--context", "context:primary-signature",
                           "--verbose=4", dmg], "dmg-policy").stderr
    if b"source=Notarized Developer ID" not in policy:
        raise ReleaseError("Gatekeeper did not accept the notarized DMG.")
    mount = plistlib.loads(commands.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen", "-plist", dmg], "mount-dmg").stdout)
    volumes = [entry["mount-point"] for entry in mount["system-entities"] if entry.get("mount-point")]
    if len(volumes) != 1:
        for volume in volumes:
            commands.run(["hdiutil", "detach", volume], "detach-unexpected-volume", required=False)
        raise ReleaseError("Expected a single mounted release volume.")
    volume = Path(volumes[0])
    try:
        verify_code(commands, volume / APP_NAME, "mounted")
        if not (volume / "Applications").is_symlink() or os.readlink(volume / "Applications") != "/Applications":
            raise ReleaseError("The Applications link is invalid.")
        if {path.name for path in volume.iterdir() if not path.name.startswith(".")} != {APP_NAME, "Applications", "Licenses"}:
            raise ReleaseError("Unexpected disk image contents.")
        for name in NOTICES:
            if (volume / "Licenses" / name).read_bytes() != (ROOT / name).read_bytes():
                raise ReleaseError("A license notice is missing or changed.")
        policy = commands.run(["spctl", "--assess", "--type", "execute", "--verbose=4", volume / APP_NAME], "mounted-app-policy").stderr
        if b"source=Notarized Developer ID" not in policy:
            raise ReleaseError("Gatekeeper did not accept the mounted app.")
    finally:
        commands.run(["hdiutil", "detach", volume], "detach-dmg")


def build(tag, directory, event):
    version = parse_tag(tag)
    revision = verify_source(tag, event)
    if directory.exists():
        raise ReleaseError("Use a new release output directory.")
    evidence = directory / "evidence"
    output = directory / "output"
    evidence.mkdir(parents=True)
    output.mkdir()
    commands = Commands(evidence)
    number = os.environ.get("GITHUB_RUN_NUMBER", "1")
    if not re.fullmatch(r"[1-9][0-9]*", number):
        raise ReleaseError("The build number must be a positive integer.")
    archive = directory / "LogLift.xcarchive"
    exported = directory / "Export"
    cache = os.environ.get("LOGBATCH_DERIVED_DATA", str(directory / "DerivedData"))
    fingerprint = os.environ.get("DEVELOPER_ID_SHA1", "")
    team = os.environ.get("APPLE_TEAM_ID", "")
    with signing_identity(commands) as key:
        options = {"method": "developer-id", "destination": "export", "signingStyle": "manual",
                   "signingCertificate": fingerprint, "teamID": team, "stripSwiftSymbols": True,
                   "manageAppVersionAndBuildNumber": False}
        export_options = directory / "ExportOptions.plist"
        export_options.write_bytes(plistlib.dumps(options))
        commands.run(["xcodebuild", "archive", "-project", "LogBatch.xcodeproj", "-scheme", "LogBatch",
                      "-configuration", "Release", "-destination", "generic/platform=macOS", "-derivedDataPath", cache,
                      "-archivePath", archive, "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_STYLE=Manual",
                      "CODE_SIGN_IDENTITY=" + fingerprint, "DEVELOPMENT_TEAM=" + team,
                      "ENABLE_HARDENED_RUNTIME=YES", "CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES",
                      "OTHER_CODE_SIGN_FLAGS=--timestamp", "ONLY_ACTIVE_ARCH=NO", "ARCHS=arm64 x86_64",
                      "MARKETING_VERSION=" + version, "CURRENT_PROJECT_VERSION=" + number], "archive")
        commands.run(["xcodebuild", "-exportArchive", "-archivePath", archive, "-exportPath", exported,
                      "-exportOptionsPlist", export_options], "export")
        app = exported / APP_NAME
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        if info["CFBundleShortVersionString"] != version or info["CFBundleVersion"] != number:
            raise ReleaseError("The exported app version does not match the requested release.")
        security = verify_code(commands, app, "exported")
        stage = directory / "DiskImage"
        stage.mkdir()
        commands.run(["ditto", app, stage / APP_NAME], "stage-app")
        (stage / "Applications").symlink_to("/Applications")
        for name in NOTICES:
            destination = stage / "Licenses" / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, destination)
        dmg = output / f"DJI-LogLift-{tag[1:]}-universal.dmg"
        commands.run(["hdiutil", "create", "-srcfolder", stage, "-format", "UDZO", "-volname", "LogLift for DJI", dmg], "create-dmg")
        commands.run(["hdiutil", "verify", dmg], "verify-image-before-submit")
        commands.run(["codesign", "--sign", fingerprint, "--timestamp", dmg], "sign-dmg")
        commands.run(["codesign", "--verify", "--strict", "--verbose=4", dmg], "verify-signature-before-submit")
        details = commands.run(["codesign", "-dvvv", dmg], "dmg-signature-details").stderr.decode()
        if f"TeamIdentifier={team}" not in details or "Timestamp=" not in details or "Authority=Developer ID Application:" not in details:
            raise ReleaseError("The DMG signature is not ready for notarization.")
        before = {"sha256": sha256(dmg), "bytes": dmg.stat().st_size, "signingDetails": details}
        (evidence / "before-notarization.json").write_text(json.dumps(before, indent=2) + "\n")
        submission = notarize(commands, dmg, key)
        commands.run(["xcrun", "stapler", "staple", dmg], "staple-dmg")
        verify_image(commands, dmg)
    if verify_source(tag, event) != revision:
        raise ReleaseError("Source changed during release verification.")
    receipt = {"tag": tag, "version": version, "build": number, "sourceCommit": revision,
               "filename": dmg.name, "sha256": sha256(dmg), "bytes": dmg.stat().st_size,
               "teamID": team, "identitySHA1": fingerprint, "notarizationID": submission,
               "notarization": "Accepted", "stapled": True, "gatekeeper": "accepted",
               "architectures": ["arm64", "x86_64"], "security": security,
               "xcode": capture(["xcodebuild", "-version"]),
               "releaseScriptSHA256": sha256(__file__), "prerelease": True,
               "productionUserPathTest": "pending on a fresh Mac or VM"}
    (output / "release.json").write_text(json.dumps(receipt, indent=2) + "\n")
    (output / "SHA256SUMS").write_text(receipt["sha256"] + "  " + dmg.name + "\n")
    print(f"Verified release candidate: {dmg.name} ({receipt['sha256']})", flush=True)


def publication_inputs(directory, tag, revision):
    parse_tag(tag)
    receipt = json.loads((directory / "release.json").read_text())
    filename = f"DJI-LogLift-{tag[1:]}-universal.dmg"
    if (receipt.get("tag") != tag or receipt.get("sourceCommit") != revision or
            receipt.get("filename") != filename or receipt.get("notarization") != "Accepted" or
            receipt.get("stapled") is not True or receipt.get("gatekeeper") != "accepted" or
            receipt.get("prerelease") is not True):
        raise ReleaseError("The artifact receipt is not approved for this tag and commit.")
    dmg = directory / filename
    if sha256(dmg) != receipt.get("sha256") or dmg.stat().st_size != receipt.get("bytes"):
        raise ReleaseError("The final artifact no longer matches its verified receipt.")
    if (directory / "SHA256SUMS").read_text() != receipt["sha256"] + "  " + filename + "\n":
        raise ReleaseError("The checksum file does not match the verified artifact.")
    return receipt, dmg


def verify_remote_tag(repo, tag, revision):
    reference = json.loads(capture(["gh", "api", f"repos/{repo}/git/ref/tags/{tag}"]))["object"]
    for _ in range(8):
        if reference["type"] == "commit":
            if reference["sha"] != revision:
                raise ReleaseError("The remote tag moved away from the verified source.")
            return
        if reference["type"] != "tag":
            break
        reference = json.loads(capture(["gh", "api", f"repos/{repo}/git/tags/{reference['sha']}"]))["object"]
    raise ReleaseError("The remote tag does not resolve to a supported commit.")


def publish(tag, directory):
    revision = verify_source(tag, "push")
    receipt, dmg = publication_inputs(directory, tag, revision)
    repo = os.environ["GITHUB_REPOSITORY"]
    verify_remote_tag(repo, tag, revision)
    existing = subprocess.run(["gh", "api", f"repos/{repo}/releases/tags/{tag}"], capture_output=True)
    if existing.returncode == 0:
        raise ReleaseError("This tag already has a Release. Existing assets will not be replaced.")
    if b"HTTP 404" not in existing.stderr:
        raise ReleaseError("Cannot confirm that the Release is absent.")
    notes = directory / "release-notes.md"
    notes.write_text(f"LogLift for DJI {tag[1:]} preview. Requires macOS 14 or later. Universal app for Apple Silicon and Intel.\n\n"
                     "Open the DMG and drag LogLift for DJI to Applications. License texts and third-party notices are included.\n\n"
                     "Developer ID signed, Apple notarization accepted, ticket stapled, and Gatekeeper verified on the final disk image and mounted app.\n\n"
                     "Clean Mac/VM quarantine-aware download, offline installation and first launch remain untested. This is a preview release.\n\n"
                     f"Source: `{revision}`. Build: {receipt['build']}. SHA-256: `{receipt['sha256']}`.\n\n"
                     "Project-owned materials use PolyForm Noncommercial, subject to retained earlier MIT permissions. DJI materials are excluded; redistribution permission remains unverified. See LICENSING.md and THIRD_PARTY_NOTICES.md in the source.\n")
    result = subprocess.run(["gh", "release", "create", tag, str(dmg), str(directory / "SHA256SUMS"),
                             "--repo", repo, "--target", revision, "--verify-tag", "--title", f"DJI LogLift {tag[1:]} Preview",
                             "--prerelease", "--latest=false", "--notes-file", str(notes)], capture_output=True, text=True)
    if result.returncode:
        raise ReleaseError("Release creation failed. Inspect its remote state before retrying.")
    verify_remote_tag(repo, tag, revision)
    published = json.loads(capture(["gh", "api", f"repos/{repo}/releases/tags/{tag}"]))
    assets = {asset["name"]: asset for asset in published["assets"]}
    if (published["draft"] or not published["prerelease"] or
            set(assets) != {dmg.name, "SHA256SUMS"} or
            assets[dmg.name]["size"] != receipt["bytes"] or
            assets[dmg.name].get("digest") != "sha256:" + receipt["sha256"]):
        raise ReleaseError("The published Release does not match the verified artifact.")
    print(result.stdout.strip())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("build", "publish"))
    parser.add_argument("--tag", required=True)
    parser.add_argument("--directory", required=True, type=Path)
    args = parser.parse_args()
    try:
        if args.operation == "build":
            build(args.tag, args.directory.resolve(), os.environ.get("GITHUB_EVENT_NAME", "workflow_dispatch"))
        else:
            publish(args.tag, args.directory.resolve())
    except (ReleaseError, KeyError, ValueError, OSError) as error:
        print(f"Release stopped: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
