"""Тесты asc_whats_new: заметки для ревьюера и перезапись текстов (KAN-96)."""
import os
import sys
import unittest
from contextlib import redirect_stdout
from io import StringIO
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import asc_whats_new as wn  # noqa: E402


class ReviewNotes(unittest.TestCase):
    def test_reads_first_code_block(self):
        notes = wn.review_notes()
        self.assertTrue(notes.startswith("ZenHab is a habit tracker."))
        self.assertNotIn("```", notes)
        self.assertLessEqual(len(notes), 4000)


class Overwrite(unittest.TestCase):
    def run_fill(self, overwrite, current):
        calls = []
        loc = {"id": "L1", "attributes": dict(current, locale="en-US")}

        def fake(method, path, **kw):
            calls.append((method, path, kw))
            if path.endswith("/appStoreVersionLocalizations"):
                return {"data": [loc]}
            if path.endswith("/appInfos"):
                return {"data": []}
            return {"data": {}}

        sec = {"Description": "new desc", "Keywords": "new,kw", "Promotional text": "promo"}
        with mock.patch.object(wn, "call", fake), mock.patch.object(wn, "sections", lambda _l: sec), \
                redirect_stdout(StringIO()):
            wn.fill_missing_texts("A1", "V1", overwrite=overwrite)
        return [c for c in calls if c[0] == "PATCH"]

    def test_keeps_filled_fields_by_default(self):
        current = {"description": "old", "keywords": "old", "promotionalText": "old", "supportUrl": "u"}
        self.assertEqual(self.run_fill(False, current), [])

    def test_overwrite_replaces_texts(self):
        current = {"description": "old", "keywords": "old", "promotionalText": "promo", "supportUrl": "u"}
        patches = self.run_fill(True, current)
        self.assertEqual(len(patches), 1)
        attrs = patches[0][2]["json"]["data"]["attributes"]
        self.assertEqual(attrs, {"description": "new desc", "keywords": "new,kw"})


if __name__ == "__main__":
    unittest.main()
