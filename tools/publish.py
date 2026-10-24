"""Validate a GitHub release, then publish its exact archive and page to Factorio.

Credentials come only from the workflow environment. No browser credentials,
private saves, or native test output are needed. See docs/development.md.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urljoin, urlsplit
from urllib.request import Request, urlopen
from uuid import uuid4
from zipfile import ZipFile

REPOSITORY = "TTLouis/factorio-production-flow"
MOD = "production-flow"
PORTAL = "https://mods.factorio.com"
ROOT = Path(__file__).resolve().parents[1]


class PublishError(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise PublishError(message)


def digest(path, algorithm="sha256"):
    return hashlib.new(algorithm, path.read_bytes()).hexdigest()


def request(url, *, method="GET", data=None, headers=None, missing=False, binary=False):
    try:
        with urlopen(Request(url, data=data, headers=headers or {}, method=method), timeout=120) as response:
            raw = response.read()
    except HTTPError as error:
        if error.code == 404 and missing:
            return None
        # Do not print response bodies, request headers or signed upload URLs.
        try:
            code = json.loads(error.read()).get("error", "")
        except (ValueError, AttributeError):
            code = ""
        safe = code if re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{0,60}", str(code)) else "request rejected"
        raise PublishError(f"Remote API HTTP {error.code}: {safe}") from None
    except (URLError, TimeoutError):
        raise PublishError("Remote API request failed or timed out; no automatic upload retry was attempted") from None
    if binary:
        return raw
    try:
        result = json.loads(raw)
    except ValueError:
        raise PublishError("Remote API returned invalid JSON") from None
    require(not result.get("error"), "Remote API rejected the operation")
    return result


def github(path, *, data=None, method="GET", content_type="application/json"):
    headers = {"Accept": "application/vnd.github+json", "User-Agent": MOD + "-publisher"}
    token = os.getenv("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = "Bearer " + token
    if data is not None:
        headers["Content-Type"] = content_type
    base = "https://uploads.github.com" if path.startswith("/uploads/") else "https://api.github.com"
    return request(base + path.removeprefix("/uploads"), method=method, data=data, headers=headers)


def release(tag):
    require(re.fullmatch(r"v\d+\.\d+\.\d+", tag or ""), "Release tag must be vMAJOR.MINOR.PATCH")
    result = github(f"/repos/{REPOSITORY}/releases/tags/{quote(tag, safe='')}")
    require(result.get("tag_name") == tag and not result.get("draft"), "Release must be published and match the requested tag")
    return result


def resolve(tag):
    if not tag:
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
        tag = event.get("release", {}).get("tag_name", "")
    info = release(tag)
    if os.getenv("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            output.write(f"tag={tag}\n")
    print(f"Selected published release {tag} (id {info['id']})")


def validate_archive(archive, source, tag):
    mod = source / "mod" / MOD
    info = json.loads((mod / "info.json").read_text())
    require(info["name"] == MOD and tag == "v" + info["version"], "Release tag and info.json version differ")
    require((mod / "LICENSE").read_bytes() == (source / "LICENSE").read_bytes(), "Packaged MIT license differs from repository license")
    expected = {p.relative_to(mod).as_posix(): p for p in mod.rglob("*")
                if p.is_file() and not {"tools", "__pycache__"}.intersection(p.relative_to(mod).parts)}
    prefix = f"{MOD}_{info['version']}/"
    with ZipFile(archive) as zipfile:
        entries = zipfile.infolist()
        require(len(entries) == len({x.filename for x in entries}), "Archive contains duplicate entries")
        require(sum(x.file_size for x in entries) <= 64 * 1024 * 1024, "Archive is unexpectedly large")
        require(set(zipfile.namelist()) == {prefix + name for name in expected}, "Archive contains missing or unexpected files")
        for name, path in expected.items():
            require(zipfile.read(prefix + name) == path.read_bytes(), f"Archive differs from release source: {name}")
        png = zipfile.read(prefix + "thumbnail.png")
        require(png[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(">II", png[16:24]) == (512, 512), "Thumbnail must be the 512px release icon")
    return info


def page(source):
    text = (source / "docs/mod-portal.md").read_text(encoding="utf-8")
    try:
        short, description = text.split("## Short description\n", 1)[1].split("## Mod page description\n", 1)
    except IndexError:
        raise PublishError("Mod Portal document is missing its description sections") from None
    short, description = short.strip(), description.strip()
    require(0 < len(short) <= 500 and description, "Mod Portal descriptions are empty or too long")
    prefix = f"https://raw.githubusercontent.com/{REPOSITORY}/main/docs/screenshots/"
    images = []
    for url in re.findall(r"!\[[^\]]*\]\(([^)]+)\)", description):
        require(url.startswith(prefix), "Description image must reference a repository screenshot")
        name = url.removeprefix(prefix)
        require(re.fullmatch(r"[\w-]+\.png", name), "Screenshot filename is invalid")
        require((source / "docs/screenshots" / name).is_file(), "Description screenshot is missing")
        if name not in images:
            images.append(name)
    require(0 < len(images) <= 10, "Expected between one and ten gallery images")
    return short, description, images


def prepare(source, tag, output):
    info = json.loads((source / "mod" / MOD / "info.json").read_text())
    require(tag == "v" + info["version"], "Release tag and source version differ")
    remote = release(tag)
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"{MOD}_{info['version']}.zip"
    assets = [x for x in remote["assets"] if x["name"] == archive.name]
    require(len(assets) <= 1, "Release contains duplicate mod assets")
    if assets:
        require(assets[0].get("state") == "uploaded", "Release asset is still uploading")
        # Public release download: never forward the API credential to a CDN.
        url = f"https://github.com/{REPOSITORY}/releases/download/{tag}/{archive.name}"
        archive.write_bytes(request(url, binary=True))
        checksum = assets[0].get("digest")
        if checksum:
            require(checksum == "sha256:" + digest(archive), "GitHub asset checksum differs")
    else:
        subprocess.run([sys.executable, str(source / "tools/build.py")], check=True)
        shutil.copyfile(source / "dist" / archive.name, archive)
    info = validate_archive(archive, source, tag)
    short, description, images = page(source)
    gallery = output / "gallery"
    gallery.mkdir(exist_ok=True)
    for name in images:
        shutil.copyfile(source / "docs/screenshots" / name, gallery / name)
    config = json.loads((ROOT / "tools/mod_portal.json").read_text())
    metadata = dict(config, title=info["title"], summary=short, description=description,
                    source_url=f"https://github.com/{REPOSITORY}")
    plan = {"repository": REPOSITORY, "tag": tag, "version": info["version"], "mod": MOD,
            "release_id": remote["id"], "archive": archive.name, "sha256": digest(archive),
            "sha1": digest(archive, "sha1"), "metadata": metadata,
            "gallery": [{"file": name, "sha1": digest(gallery / name, "sha1"),
                         "sha256": digest(gallery / name)} for name in images]}
    (output / "plan.json").write_text(json.dumps(plan, indent=2), encoding="utf-8")
    print(f"Verified {archive.name}: SHA256 {plan['sha256']}; {len(images)} screenshots; category: {config['category']}; tags: {', '.join(config['tags']) or 'none'}")


def multipart(fields, file=None):
    boundary = "----production-flow-" + uuid4().hex
    body = bytearray()
    for name, value in fields.items():
        values = value if isinstance(value, list) else [value]
        for item in values:
            body.extend(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{item}\r\n'.encode())
    if file:
        field, path = file
        body.extend(f'--{boundary}\r\nContent-Disposition: form-data; name="{field}"; filename="{path.name}"\r\nContent-Type: application/octet-stream\r\n\r\n'.encode())
        body.extend(path.read_bytes())
        body.extend(b"\r\n")
    body.extend(f"--{boundary}--\r\n".encode())
    return bytes(body), "multipart/form-data; boundary=" + boundary


def portal_post(path, fields, *, file=None, signed_url=None):
    body, content_type = multipart(fields, file)
    headers = {"Content-Type": content_type, "User-Agent": MOD + "-publisher"}
    if signed_url:
        parsed = urlsplit(signed_url)
        require(parsed.scheme == "https" and parsed.hostname and not parsed.username and not parsed.password,
                "Portal returned an invalid upload URL")
        url = signed_url
    else:
        headers["Authorization"] = "Bearer " + os.environ["FACTORIO_API_KEY"]
        url = PORTAL + path
    return request(url, method="POST", data=body, headers=headers)


def portal_state():
    return request(f"{PORTAL}/api/mods/{MOD}/full", missing=True)


def verify_bundle(bundle):
    plan = json.loads((bundle / "plan.json").read_text())
    require(plan["repository"] == REPOSITORY and plan["mod"] == MOD, "Bundle belongs to another repository or mod")
    require(re.fullmatch(r"\d+\.\d+\.\d+", plan["version"]) and plan["tag"] == "v" + plan["version"], "Invalid bundle version")
    require(plan["archive"] == f"{MOD}_{plan['version']}.zip", "Invalid archive filename")
    require(digest(bundle / plan["archive"]) == plan["sha256"], "Verified ZIP changed after validation")
    require(digest(bundle / plan["archive"], "sha1") == plan["sha1"], "Verified ZIP SHA1 differs")
    for entry in plan["gallery"]:
        require(re.fullmatch(r"[\w-]+\.png", entry["file"]), "Invalid gallery filename")
        require(digest(bundle / "gallery" / entry["file"]) == entry["sha256"], "Screenshot changed after validation")
    return plan


def existing_release(state, plan):
    for entry in (state or {}).get("releases", []):
        if entry["version"] == plan["version"]:
            require(entry["sha1"] == plan["sha1"], "Portal already has this version with a different ZIP; choose a new version")
            return True
    return False


def deploy(bundle):
    plan = verify_bundle(bundle)
    require(os.getenv("FACTORIO_API_KEY"), "Add the FACTORIO_API_KEY repository secret before publishing")
    remote = release(plan["tag"])
    require(remote["id"] == plan["release_id"], "GitHub release changed after validation")
    assets = [x for x in remote["assets"] if x["name"] == plan["archive"]]
    if assets:
        require(len(assets) == 1, "GitHub release has duplicate assets")
        checksum = assets[0].get("digest")
        if checksum:
            require(checksum == "sha256:" + plan["sha256"], "Release asset changed after validation")
        else:
            raw = request(f"https://github.com/{REPOSITORY}/releases/download/{plan['tag']}/{plan['archive']}", binary=True)
            require(hashlib.sha256(raw).hexdigest() == plan["sha256"], "Release asset changed after validation")
    else:
        path = f"/uploads/repos/{REPOSITORY}/releases/{plan['release_id']}/assets?" + urlencode({"name": plan["archive"]})
        uploaded = github(path, data=(bundle / plan["archive"]).read_bytes(), method="POST", content_type="application/zip")
        require(uploaded.get("state") == "uploaded", "GitHub release asset did not finish uploading")
    state = portal_state()
    if not existing_release(state, plan):
        if state and state.get("releases"):
            version = lambda v: tuple(map(int, v.split(".")))
            require(max(version(x["version"]) for x in state["releases"]) < version(plan["version"]), "Refusing to publish an older version")
        endpoint = "/api/v2/mods/releases/init_upload" if state else "/api/v2/mods/init_publish"
        start = portal_post(endpoint, {"mod": MOD})
        fields = {} if state else {k: v for k, v in plan["metadata"].items() if k in {"description", "category", "license", "source_url"}}
        finished = portal_post("", fields, file=("file", bundle / plan["archive"]), signed_url=start["upload_url"])
        require(finished.get("success") is True, "Portal did not confirm the mod upload")
        print(f"Uploaded {MOD} {plan['version']}")
    else:
        print("Exact release already exists; resuming page and gallery synchronization")
    state = portal_state()
    require(existing_release(state, plan), "Portal release does not match the published GitHub ZIP")
    current = {x["id"]: x for x in state.get("images", [])}
    desired, description = [], plan["metadata"]["description"]
    for entry in plan["gallery"]:
        image = current.get(entry["sha1"])
        if not image:
            start = portal_post("/api/v2/mods/images/add", {"mod": MOD})
            image = portal_post("", {}, file=("image", bundle / "gallery" / entry["file"]), signed_url=start["upload_url"])
            require(image.get("id") == entry["sha1"] and image.get("url"), "Portal image differs from the approved screenshot")
        desired.append(image["id"])
        original = f"https://raw.githubusercontent.com/{REPOSITORY}/main/docs/screenshots/{entry['file']}"
        description = description.replace(original, urljoin(PORTAL, image["url"]))
    # Keep any manually-added images after the release's approved gallery.
    desired.extend(key for key in current if key not in desired)
    edited = portal_post("/api/v2/mods/images/edit", {"mod": MOD, "images": ",".join(desired)})
    require(edited.get("success") is True, "Portal did not confirm gallery ordering")
    fields = dict(plan["metadata"], mod=MOD, description=description)
    edited = portal_post("/api/v2/mods/edit_details", fields)
    require(edited.get("success") is True, "Portal did not confirm the page update")
    final = portal_state()
    require(existing_release(final, plan), "Final release verification failed")
    require(final.get("description", "").replace("\r\n", "\n").strip() == description.strip(), "Final description differs from the approved page")
    require(set(plan["metadata"]["tags"]) == set(final.get("tags", [])), "Portal tags differ from the requested classification")
    require(set(desired).issubset({x["id"] for x in final.get("images", [])}), "Portal gallery is incomplete")
    url = f"{PORTAL}/mod/{MOD}"
    print(f"Published and verified {url} version {plan['version']} SHA256 {plan['sha256']}")
    if os.getenv("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as summary:
            summary.write(f"Published [{MOD} {plan['version']}]({url}) from GitHub release {plan['tag']}.\n\nSHA256: `{plan['sha256']}`\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    select = commands.add_parser("resolve")
    select.add_argument("--tag", default="")
    stage = commands.add_parser("prepare")
    stage.add_argument("--tag", required=True)
    stage.add_argument("--source", type=Path, required=True)
    stage.add_argument("--output", type=Path, required=True)
    publish = commands.add_parser("deploy")
    publish.add_argument("--bundle", type=Path, required=True)
    args = parser.parse_args()
    require(os.getenv("GITHUB_REPOSITORY", REPOSITORY) == REPOSITORY, "Publisher is restricted to its intended repository")
    if args.command == "resolve":
        resolve(args.tag)
    elif args.command == "prepare":
        prepare(args.source.resolve(), args.tag, args.output.resolve())
    else:
        deploy(args.bundle.resolve())


if __name__ == "__main__":
    try:
        main()
    except (PublishError, KeyError, ValueError) as error:
        print(f"Publishing stopped: {error}", file=sys.stderr)
        raise SystemExit(1)
