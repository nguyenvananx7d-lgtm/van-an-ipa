#!/usr/bin/env python3
"""Regression tests for the standalone dump-to-IFix project."""

from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from update_from_dump import discover_bindings  # noqa: E402
from verify_ifix_patch import Verifier, parse_patch  # noqa: E402


class BindingDiscoveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.dump = ROOT / "dumps" / "unknown_package_name_1.132.1.cs"
        cls.placeholders, cls.rows, cls.details = discover_bindings(cls.dump)

    def test_current_dump_bindings(self) -> None:
        expected = {
            "MATCH_TYPE": "JMAGGLCNGIG",
            "MATCH_PLAYERS_METHOD": "ILPNGCMEFFI",
            "AIM_INFO_TYPE": "CGKJLKPMGDJ",
            "AIM_HIT_TYPE": "LKOOALMKJND",
            "SPEED_TYPE": "KGCCMFBFCAC",
            "PLAYER_AIM_INFO_FIELD": "FDMIEDDNCEC",
            "SCENE_MENU_FIELD": "AFHAOIAPPNB",
            "SCENE_POSITION_FIELD": "OHPFLEDNOJK",
            "SCENE_STATE_FIELD": "DIGCJIKHGJP",
        }
        for name, value in expected.items():
            self.assertEqual(value, self.placeholders[name])

    def test_complete_retarget_table(self) -> None:
        kinds = [row[0] for row in self.rows]
        self.assertEqual(4, kinds.count("TYPE"))
        self.assertEqual(1, kinds.count("METHOD"))
        self.assertEqual(15, kinds.count("FIELD"))


class GeneratedSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = (ROOT / "generated" / "ESPLogic.cs").read_text(encoding="utf-8")

    def test_menu_is_present(self) -> None:
        for value in (
            "ESP CONTROL", "Enable ESP", "Player box", "Top tracer",
            "Health bar", "Player name", "Distance", "RESET DEFAULTS", "HIDE MENU",
        ):
            self.assertIn(value, self.source)
        self.assertIn("Input.touchCount >= 3", self.source)

    def test_removed_features_are_absent(self) -> None:
        for value in (
            "Fast reload", "Fake lag", "Silent aim", "Aim system", "No recoil",
            "Fast parachute", "Speed running", "FastReloadStarted",
            "FastImmediateReloadStarted", "SyncStatePosition", "GetSyncStatePos",
        ):
            self.assertNotIn(value, self.source)

    def test_no_unexpanded_placeholders(self) -> None:
        self.assertNotIn("{{", self.source)


class PatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.patch_path = ROOT / "dist" / "Assembly-CSharp-patch.bytes"
        cls.dump_path = ROOT / "dumps" / "unknown_package_name_1.132.1.cs"
        if not cls.patch_path.is_file():
            raise unittest.SkipTest("build dist/Assembly-CSharp-patch.bytes first")
        cls.patch, cls.dump_index, cls.parse_issues = parse_patch(
            cls.patch_path, cls.dump_path, "target"
        )

    def test_patch_verifies(self) -> None:
        self.assertFalse([issue for issue in self.parse_issues if issue.severity == "error"])
        verifier = Verifier(copy.deepcopy(self.patch), self.dump_index)
        verifier.verify()
        self.assertEqual([], [issue.as_dict() for issue in verifier.issues])

    def test_redirect_surface(self) -> None:
        redirects = self.patch["redirects"]
        names = {record["method"].name for record in redirects}
        self.assertEqual(2, len(redirects))
        self.assertEqual({
            "IsReallyInStealth", "OnGUI",
        }, names)

    def test_removed_features_are_absent(self) -> None:
        method_names = {method.name for method in self.patch["external_methods"]}
        for name in (
            "GetSyncStatePos", "OnWeaponReloadStarted",
            "OnWeaponReloadImmediateStarted", "SendStartReload", "IsFiring",
        ):
            self.assertNotIn(name, method_names)
        self.assertNotIn("Fast reload x3", self.patch["strings"])
        self.assertNotIn("Fake lag (fire)", self.patch["strings"])
        self.assertNotIn("Silent aim", self.patch["strings"])
        self.assertNotIn("Aim system", self.patch["strings"])
        self.assertNotIn("No recoil", self.patch["strings"])
        self.assertNotIn("Fast parachute", self.patch["strings"])
        self.assertNotIn("Speed running x3", self.patch["strings"])


if __name__ == "__main__":
    unittest.main()
