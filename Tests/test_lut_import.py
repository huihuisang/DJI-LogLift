import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("lut_import", Path(__file__).resolve().parents[1] / "script/sync_dji_luts.py")
IMPORTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(IMPORTER)


class LUTImportTests(unittest.TestCase):
    def test_provenance_removes_download_credentials_and_marks_changed_fields(self):
        source = {"files": [{"resolvedURL": "https://example.com/lut.cube?version=1&AUTH_KEY=example&token=example"}],
                  "sha256": "unchanged"}
        result = IMPORTER.public_provenance(source)
        self.assertEqual(result["files"][0]["resolvedURL"], "https://example.com/lut.cube?version=1")
        self.assertEqual(result["files"][0]["sanitizedURLFields"], ["resolvedURL"])
        self.assertEqual(result["sha256"], "unchanged")
        self.assertIn("AUTH_KEY=example", source["files"][0]["resolvedURL"])
        self.assertEqual(IMPORTER.public_provenance(result), result)

    def test_provenance_preserves_public_urls_and_non_url_values(self):
        source = {"sourcePage": "https://example.com/downloads?version=1%202", "version": "token=example",
                  "nested": [None, 1, True, {"name": "Camera"}]}
        self.assertEqual(IMPORTER.public_provenance(source), source)

    def test_valid_cube_and_input_range(self):
        text = "LUT_3D_SIZE 2\nLUT_3D_INPUT_RANGE -1 2\n" + "0 0 0\n" * 8
        info = IMPORTER.cube_info(text.encode())
        self.assertEqual(info["sampleCount"], 8)
        self.assertEqual(info["domainMin"], [-1, -1, -1])
        self.assertEqual(info["domainMax"], [2, 2, 2])

    def test_shaper_and_non_utf8_title(self):
        text = 'TITLE "胶片"\nLUT_1D_SIZE 2\nLUT_1D_INPUT_RANGE 0 1\n0 0 0\n1 1 1\n'
        info = IMPORTER.cube_info(text.encode("gb18030"))
        self.assertEqual(info["shaperDimension"], 2)
        self.assertIsNone(info["dimension"])
        self.assertEqual(info["textEncoding"], "gb18030")

    def test_rejects_malformed_cubes(self):
        for text in ("LUT_3D_SIZE 2\n0 0 0\n", "LUT_3D_SIZE 2\n" + "nan 0 0\n" * 8,
                     "LUT_3D_SIZE 129\n", "LUT_1D_SIZE 2\nLUT_1D_INPUT_RANGE 1 0\n"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                IMPORTER.cube_info(text.encode())

    def test_recording_profiles_and_creative_luts_stay_distinct(self):
        for name, expected in (
            ("D-Log M to Rec.709 LUT", ("technical", "dlogM", "rec709")),
            ("D-LogM to Rec.709 LUT", ("technical", "dlogM", "rec709")),
            ("D-Log2 to Rec.709 LUT", ("technical", "dlog2", "rec709")),
            ("D-Log to Rec.2020 HLG LUT", ("technical", "dlog", "rec2020HLG")),
            ("Rec.709 to Color Grading LUTs", ("creative", "rec709", "rec709")),
        ):
            self.assertEqual(IMPORTER.transform_kind({"id": "test", "name": name}), expected)

    def test_missing_index_never_looks_like_an_empty_success(self):
        with self.assertRaises(ValueError):
            IMPORTER.discover("<html>Unavailable</html>")


if __name__ == "__main__":
    unittest.main()

