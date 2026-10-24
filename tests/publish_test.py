"""Release safety and resumability checks; no network or live credentials."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

SPEC = importlib.util.spec_from_file_location("publisher", Path(__file__).resolve().parents[1] / "tools/publish.py")
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        scratch = Path(__file__).resolve().parent / "out/publish-fixtures"
        scratch.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=scratch)
        assert Path(self.temp.name).resolve().is_relative_to(scratch.resolve())
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        mod = self.root / "mod/production-flow"
        mod.mkdir(parents=True)
        (self.root / "LICENSE").write_text("MIT fixture")
        (mod / "LICENSE").write_text("MIT fixture")
        (mod / "info.json").write_text(json.dumps({"name": "production-flow", "version": "0.1.1", "title": "Production Flow (Beta)"}))
        (mod / "control.lua").write_text("return true")
        png = b"\x89PNG\r\n\x1a\n" + b"\0\0\0\rIHDR" + struct.pack(">II", 512, 512)
        (mod / "thumbnail.png").write_bytes(png)
        screenshots = self.root / "docs/screenshots"
        screenshots.mkdir(parents=True)
        (screenshots / "test.png").write_bytes(png)
        self.description = f"Approved description.\n\n![Test](https://raw.githubusercontent.com/{P.REPOSITORY}/main/docs/screenshots/test.png)"
        (self.root / "docs/mod-portal.md").write_text("## Short description\nShort summary\n\n## Mod page description\n" + self.description)
        self.archive = self.root / "production-flow_0.1.1.zip"
        with ZipFile(self.archive, "w") as z:
            for path in mod.iterdir():
                z.write(path, "production-flow_0.1.1/" + path.name)
        self.remote = {"id": 123, "tag_name": "v0.1.1", "draft": False,
                       "assets": [{"name": self.archive.name, "state": "uploaded", "digest": "sha256:" + P.digest(self.archive)}]}

    def bundle(self):
        output = self.root / "bundle"
        with patch.object(P, "release", return_value=self.remote), patch.object(P, "request", return_value=self.archive.read_bytes()):
            P.prepare(self.root, "v0.1.1", output)
        return output

    def test_valid_archive_and_page(self):
        self.assertEqual(P.validate_archive(self.archive, self.root, "v0.1.1")["version"], "0.1.1")
        summary, text, images = P.page(self.root)
        self.assertEqual((summary, text, images), ("Short summary", self.description, ["test.png"]))

    def test_reject_tag_mismatch(self):
        with self.assertRaisesRegex(P.PublishError, "version differ"):
            P.validate_archive(self.archive, self.root, "v0.1.2")

    def test_reject_unexpected_and_duplicate_files(self):
        with ZipFile(self.archive, "a") as z:
            z.writestr("production-flow_0.1.1/scripts/save_test.lua", "private test hook")
        with self.assertRaisesRegex(P.PublishError, "unexpected files"):
            P.validate_archive(self.archive, self.root, "v0.1.1")

    def test_reject_changed_runtime(self):
        (self.root / "mod/production-flow/control.lua").write_text("changed since test")
        with self.assertRaisesRegex(P.PublishError, "differs from release source"):
            P.validate_archive(self.archive, self.root, "v0.1.1")

    def test_text_line_endings_are_portable_but_images_are_exact(self):
        self.assertTrue(P.same_source("control.lua", b"a\r\nb\r\n", b"a\nb\n"))
        self.assertTrue(P.same_source("LICENSE", b"MIT\r\n", b"MIT\n"))
        self.assertFalse(P.same_source("control.lua", b"changed\r\n", b"original\n"))
        self.assertFalse(P.same_source("icon.png", b"a\r\nb", b"a\nb"))
        self.assertFalse(P.same_source("control.lua", b"\xff\r\n", b"\xff\n"))

    def test_reject_changed_github_checksum(self):
        remote = copy.deepcopy(self.remote)
        remote["assets"][0]["digest"] = "sha256:wrong"
        with patch.object(P, "release", return_value=remote), patch.object(P, "request", return_value=self.archive.read_bytes()):
            with self.assertRaisesRegex(P.PublishError, "checksum differs"):
                P.prepare(self.root, "v0.1.1", self.root / "bad")

    def test_reject_draft_or_invalid_tag(self):
        with self.assertRaisesRegex(P.PublishError, "Release tag"):
            P.release("v0.1.1\nmalicious=true")
        with patch.object(P, "github", return_value=dict(self.remote, draft=True)):
            with self.assertRaisesRegex(P.PublishError, "must be published"):
                P.release("v0.1.1")

    def test_bundle_detects_archive_and_screenshot_changes(self):
        bundle = self.bundle()
        archive = bundle / self.archive.name
        original = archive.read_bytes()
        archive.write_bytes(original + b"changed")
        with self.assertRaisesRegex(P.PublishError, "ZIP changed"):
            P.verify_bundle(bundle)
        archive.write_bytes(original)
        (bundle / "gallery/test.png").write_bytes(b"changed")
        with self.assertRaisesRegex(P.PublishError, "Screenshot changed"):
            P.verify_bundle(bundle)

    def test_signed_upload_does_not_receive_api_key(self):
        with patch.dict(os.environ, {"FACTORIO_API_KEY": "private-key"}, clear=True), patch.object(P, "request", return_value={}) as call:
            P.portal_post("", {}, signed_url="https://upload.example/opaque-token")
            self.assertNotIn("Authorization", call.call_args.kwargs["headers"])
            P.portal_post("/api/v2/mods/init_publish", {"mod": P.MOD})
            self.assertEqual(call.call_args.kwargs["headers"]["Authorization"], "Bearer private-key")
            with self.assertRaisesRegex(P.PublishError, "invalid upload URL"):
                P.portal_post("", {}, signed_url="http://upload.example/not-https")

    def test_multipart_tags_are_repeated_fields(self):
        body, content_type = P.multipart({"tags": ["manufacturing", "fluids", "logistic-network"]})
        self.assertEqual(body.count(b'name="tags"'), 3)
        self.assertIn("multipart/form-data; boundary=", content_type)

    def test_wait_for_delayed_public_metadata(self):
        with patch.object(P, "portal_state", side_effect=[None, {"ready": False}, {"ready": True}]), \
             patch.object(P.time, "sleep") as sleep:
            result = P.wait_for_portal(lambda state: state and state.get("ready"), "not ready")
        self.assertTrue(result["ready"])
        self.assertEqual(sleep.call_count, 2)

    def test_public_verification_has_a_bounded_timeout(self):
        with patch.object(P, "portal_state", return_value={}), patch.object(P.time, "sleep") as sleep:
            with self.assertRaisesRegex(P.PublishError, "not ready"):
                P.wait_for_portal(lambda state: False, "not ready")
        self.assertEqual(sleep.call_count, 7)

    def deploy(self, bundle, fake):
        with patch.dict(os.environ, {"FACTORIO_API_KEY": "test-key"}, clear=True), \
             patch.object(P, "release", return_value=self.remote), \
             patch.object(P, "portal_state", side_effect=lambda: fake.state), \
             patch.object(P, "portal_post", side_effect=fake.post):
            P.deploy(bundle)

    def test_first_publication_and_idempotent_rerun(self):
        bundle = self.bundle()
        fake = FakePortal(P.verify_bundle(bundle))
        self.deploy(bundle, fake)
        self.deploy(bundle, fake)
        self.assertEqual(fake.uploads, 1)
        self.assertEqual(fake.image_uploads, 1)
        self.assertIn("/api/v2/mods/init_publish", fake.calls)
        self.assertEqual(fake.state["tags"], [])
        self.assertIn("https://cdn.example/test.png", fake.state["description"])

    def test_existing_mod_uses_release_upload(self):
        bundle = self.bundle()
        fake = FakePortal(P.verify_bundle(bundle))
        fake.state = {"releases": [{"version": "0.1.0", "sha1": "old"}], "images": []}
        self.deploy(bundle, fake)
        self.assertIn("/api/v2/mods/releases/init_upload", fake.calls)
        self.assertNotIn("/api/v2/mods/init_publish", fake.calls)

    def test_interrupted_page_update_resumes_without_reupload(self):
        bundle = self.bundle()
        fake = FakePortal(P.verify_bundle(bundle))
        fake.fail_details = True
        with self.assertRaisesRegex(P.PublishError, "interrupted"):
            self.deploy(bundle, fake)
        fake.fail_details = False
        self.deploy(bundle, fake)
        self.assertEqual((fake.uploads, fake.image_uploads), (1, 1))

    def test_same_version_different_zip_and_downgrade_rejected(self):
        bundle = self.bundle()
        fake = FakePortal(P.verify_bundle(bundle))
        fake.state = {"releases": [{"version": "0.1.1", "sha1": "different"}]}
        with self.assertRaisesRegex(P.PublishError, "different ZIP"):
            self.deploy(bundle, fake)
        self.assertEqual(fake.uploads, 0)
        fake.state = {"releases": [{"version": "0.1.2", "sha1": "newer"}]}
        with self.assertRaisesRegex(P.PublishError, "older version"):
            self.deploy(bundle, fake)

    def test_preserve_manually_added_gallery_images(self):
        bundle = self.bundle()
        fake = FakePortal(P.verify_bundle(bundle))
        fake.state = {"releases": [], "images": [{"id": "manual", "url": "https://cdn.example/manual.png"}]}
        self.deploy(bundle, fake)
        self.assertIn("manual", fake.order)

    def test_missing_secret_cannot_publish(self):
        bundle = self.bundle()
        with patch.dict(os.environ, {}, clear=True), patch.object(P, "portal_post") as post:
            with self.assertRaisesRegex(P.PublishError, "FACTORIO_API_KEY"):
                P.deploy(bundle)
        post.assert_not_called()


class FakePortal:
    def __init__(self, plan):
        self.plan = plan
        self.state = None
        self.calls = []
        self.uploads = self.image_uploads = 0
        self.fail_details = False
        self.order = []

    def post(self, path, fields, *, file=None, signed_url=None):
        self.calls.append(path)
        if path.endswith("init_publish") or path.endswith("init_upload"):
            return {"upload_url": "https://upload.example/release"}
        if signed_url == "https://upload.example/release":
            self.uploads += 1
            if self.state is None:
                self.state = {"releases": [], "images": []}
            self.state["releases"].append({"version": self.plan["version"], "sha1": self.plan["sha1"]})
            return {"success": True}
        if path.endswith("images/add"):
            return {"upload_url": "https://upload.example/image"}
        if signed_url == "https://upload.example/image":
            self.image_uploads += 1
            image = {"id": P.digest(file[1], "sha1"), "url": "https://cdn.example/test.png"}
            self.state["images"].append(image)
            return image
        if path.endswith("images/edit"):
            self.order = fields["images"].split(",")
            return {"success": True}
        if path.endswith("edit_details"):
            if self.fail_details:
                raise P.PublishError("Simulated interrupted page update")
            self.state.update(fields)
            return {"success": True}
        raise AssertionError(f"Unexpected portal operation: {path}")


if __name__ == "__main__":
    unittest.main()
