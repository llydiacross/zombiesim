"""Exercise the calling-card catalogue and static-data integration offline."""

import copy
import json
import unittest
from pathlib import Path

from tests.glua.harness import FixtureRunner
from tests.phase_d.test_profession_balance import ProfessionFixture


ROOT = Path(__file__).resolve().parents[2]
CATALOGUE = ROOT / "content" / "data_static" / "calling_cards.json"
ZERO_HASH = "0" * 64


class CallingCardTests(unittest.TestCase):
    def setUp(self):
        self.runner = FixtureRunner(ROOT, ["gamemode/sh_calling_cards.lua"])
        self.lua = self.runner.lua
        self.runner.load("gamemode/sh_calling_cards.lua")
        self.cards = self.lua.globals().ZM_CallingCards
        self.installed = json.loads(CATALOGUE.read_text(encoding="utf-8-sig"))
        defaults = {card["id"]: card for card in self.installed["cards"] if card["source"] == "builtin"}
        self.data = {
            "schemaVersion": 1,
            "cards": [copy.deepcopy(defaults["background_default"]), copy.deepcopy(defaults["detail_default"])],
            "aliases": {},
            "ownedFiles": [],
        }

    def to_lua(self, value):
        if isinstance(value, dict):
            return self.lua.table_from({key: self.to_lua(item) for key, item in value.items()})
        if isinstance(value, list):
            return self.lua.table_from([self.to_lua(item) for item in value])
        return value

    def validate(self, data=None, missing=()):
        data = self.data if data is None else data
        missing = set(missing)
        paths = {"materials/" + card["material"] for card in data.get("cards", []) if "material" in card}
        callback = self.lua.eval("function(check) return function(path) return check(path) end end")(
            lambda path: str(path) in paths and str(path) not in missing
        )
        return self.cards.Validate(self.to_lua(data), callback)

    def messages(self, errors):
        return [(issue["path"], issue["message"]) for issue in errors.values()]

    def with_artist_cards(self):
        data = copy.deepcopy(self.data)
        data["cards"].extend([
            {
                "id": "background_custom", "name": "Custom", "category": "background",
                "source": "finished", "material": "scoreboard/backgrounds/custom_background.png",
                "bytes": 12, "sha256": ZERO_HASH, "questReward": True,
            },
            {
                "id": "detail_mark", "name": "Mark", "category": "detail",
                "source": "generated", "material": "scoreboard/details/generated_detail_mark.png",
                "bytes": 15, "sha256": ZERO_HASH, "questReward": True,
            },
        ])
        data["ownedFiles"] = [
            {"material": card["material"], "bytes": card["bytes"], "sha256": card["sha256"]}
            for card in data["cards"] if card["source"] != "builtin"
        ]
        return data

    def test_existing_defaults_build_a_catalogue(self):
        catalogue, errors = self.validate(self.installed)
        self.assertEqual(len(errors), 0)
        self.assertEqual(catalogue.byId.background_default.material, "scoreboard/backgrounds/default.png")
        self.assertEqual(catalogue.byId.detail_default.material, "scoreboard/details/default.png")

    def test_shop_prices_are_optional_whole_credit_amounts_on_non_defaults(self):
        data = self.with_artist_cards()
        data["cards"][2]["shopCredits"] = 125
        catalogue, errors = self.validate(data)
        self.assertEqual(len(errors), 0)
        self.assertEqual(catalogue.byId.background_custom.shopCredits, 125)
        self.assertIsNone(catalogue.byId.detail_mark.shopCredits)
        for value in (0, -1, 1.5, 1000001, "125", True):
            with self.subTest(value=value):
                invalid = copy.deepcopy(data)
                invalid["cards"][2]["shopCredits"] = value
                catalogue, errors = self.validate(invalid)
                self.assertIsNone(catalogue)
                self.assertTrue(any("shopCredits" in path for path, _ in self.messages(errors)))
        data["cards"][0]["shopCredits"] = 1
        catalogue, errors = self.validate(data)
        self.assertIsNone(catalogue)
        self.assertTrue(any("shopCredits" in path for path, _ in self.messages(errors)))

    def test_networked_ids_are_bounded(self):
        data = self.with_artist_cards()
        data["cards"][2]["id"] = "background_" + "a" * 189
        catalogue, errors = self.validate(data)
        self.assertIsNone(catalogue)
        self.assertTrue(any(path == "cards[3].id" for path, _ in self.messages(errors)))

    def test_explicit_acquisition_modes_are_validated(self):
        data = self.with_artist_cards()
        data["cards"][2].update(shopCredits=100, questReward=False)
        catalogue, errors = self.validate(data)
        self.assertEqual(len(errors), 0)
        self.assertFalse(catalogue.byId.background_custom.questReward)
        self.assertTrue(catalogue.byId.detail_mark.questReward)
        data["cards"][2]["questReward"] = True
        catalogue, errors = self.validate(data)
        self.assertEqual(len(errors), 0)
        self.assertTrue(catalogue.byId.background_custom.questReward)
        for value in (None, "true", 1, False):
            with self.subTest(value=value):
                invalid = copy.deepcopy(data)
                invalid["cards"][3]["questReward"] = value
                catalogue, errors = self.validate(invalid)
                self.assertIsNone(catalogue)
                self.assertTrue(len(errors) > 0)
        data["cards"][0]["questReward"] = True
        catalogue, errors = self.validate(data)
        self.assertIsNone(catalogue)
        self.assertTrue(any("questReward" in path for path, _ in self.messages(errors)))

    def test_generated_finished_and_chained_aliases_resolve(self):
        data = self.with_artist_cards()
        data["aliases"] = {
            "background_old": "background_custom",
            "background_older": "background_old",
        }
        catalogue, errors = self.validate(data)
        self.assertEqual(len(errors), 0)
        card, status = self.cards.Resolve(catalogue, "background_older", "background")
        self.assertEqual((card.id, status), ("background_custom", "alias"))
        card, status = self.cards.Resolve(catalogue, "detail_mark", "detail")
        self.assertEqual((card.id, status), ("detail_mark", "available"))

    def test_missing_selection_falls_back_without_changing_stored_id(self):
        stored = "background_custom"
        missing, errors = self.validate()
        self.assertEqual(len(errors), 0)
        card, status = self.cards.Resolve(missing, stored, "background")
        self.assertEqual((card.id, status, stored), ("background_default", "missing", "background_custom"))
        restored, errors = self.validate(self.with_artist_cards())
        self.assertEqual(len(errors), 0)
        card, status = self.cards.Resolve(restored, stored, "background")
        self.assertEqual((card.id, status, stored), ("background_custom", "available", "background_custom"))

    def test_defaults_and_invalid_categories_have_distinct_statuses(self):
        catalogue, _ = self.validate()
        card, status = self.cards.Resolve(catalogue, None, "detail")
        self.assertEqual((card.id, status), ("detail_default", "default"))
        card, status = self.cards.Resolve(catalogue, "background_default", "detail")
        self.assertEqual((card.id, status), ("detail_default", "missing"))
        card, status = self.cards.Resolve(catalogue, "", "unsupported")
        self.assertIsNone(card)
        self.assertEqual(status, "invalid_category")
        card, status = self.cards.Resolve(None, "", "detail")
        self.assertIsNone(card)
        self.assertEqual(status, "catalogue_unavailable")

    def test_duplicate_unsafe_and_missing_materials_fail(self):
        data = self.with_artist_cards()
        data["cards"].append(copy.deepcopy(data["cards"][2]))
        data["cards"][3]["material"] = "scoreboard/details/../bad.png"
        missing = ["materials/scoreboard/backgrounds/custom_background.png"]
        catalogue, errors = self.validate(data, missing)
        self.assertIsNone(catalogue)
        messages = self.messages(errors)
        self.assertTrue(any("duplicates a card ID" in message for _, message in messages))
        self.assertTrue(any("safe material path" in message for _, message in messages))
        self.assertTrue(any("material file is missing" in message for _, message in messages))

    def test_ownership_and_default_impersonation_fail(self):
        data = self.with_artist_cards()
        data["ownedFiles"][0]["sha256"] = "1" * 64
        data["cards"][0]["source"] = "finished"
        catalogue, errors = self.validate(data)
        self.assertIsNone(catalogue)
        messages = self.messages(errors)
        self.assertTrue(any("does not match active material" in message for _, message in messages))
        self.assertTrue(any("only the built-in" in message for _, message in messages))
        self.assertTrue(any("must contain the built-in" in message for _, message in messages))

    def test_bad_aliases_and_cycles_are_rejected(self):
        for aliases, expected in (
            ({"background_old": "background_missing"}, "unavailable"),
            ({"background_a": "background_b", "background_b": "background_a"}, "cycle"),
            ({"background_old": "detail_default"}, "same category"),
            ({"background_default": "background_default"}, "unused ID"),
        ):
            with self.subTest(aliases=aliases):
                data = copy.deepcopy(self.data)
                data["aliases"] = aliases
                catalogue, errors = self.validate(data)
                self.assertIsNone(catalogue)
                self.assertTrue(any(expected in message for _, message in self.messages(errors)))

    def test_resolver_cannot_loop_on_a_corrupt_alias_table(self):
        catalogue, _ = self.validate()
        catalogue.aliases.background_old = "background_loop"
        catalogue.aliases.background_loop = "background_old"
        card, status = self.cards.Resolve(catalogue, "background_old", "background")
        self.assertEqual((card.id, status), ("background_default", "invalid_alias"))

    def test_bad_schema_digest_and_unknown_fields_are_rejected(self):
        data = copy.deepcopy(self.data)
        data["schemaVersion"] = 2
        data["cards"][0]["sha256"] = "not-a-hash"
        data["cards"][1]["extra"] = True
        catalogue, errors = self.validate(data)
        self.assertIsNone(catalogue)
        messages = self.messages(errors)
        self.assertTrue(any(path == "schemaVersion" for path, _ in messages))
        self.assertTrue(any("SHA-256" in message for _, message in messages))
        self.assertTrue(any("not a recognised field" in message for _, message in messages))

    def test_control_character_in_display_name_is_rejected(self):
        data = copy.deepcopy(self.data)
        data["cards"][0]["name"] = "Default\x7f"
        catalogue, errors = self.validate(data)
        self.assertIsNone(catalogue)
        self.assertTrue(any(path == "cards[1].name" for path, _ in self.messages(errors)))

    def test_static_reload_rejects_bad_catalogue_and_keeps_registry(self):
        fixture = ProfessionFixture()
        try:
            static = fixture.globals.ZM_StaticData
            before = static.GetRegistry(static)
            self.assertIsNotNone(before)
            files = fixture.globals.table.Copy(static.Files)
            files.callingCards = "gamemodes/zombiesim/tests/static_data/bad_calling_cards.json"
            loaded, report = static.Reload(static, files)
            self.assertFalse(loaded)
            self.assertTrue(fixture.lua.eval("function(a, b) return a == b end")(before, static.GetRegistry(static)))
            issues = [(issue["file"], issue["path"], issue["message"]) for issue in report.errors.values()]
            self.assertTrue(any(name == "calling_cards.json" and "duplicates a card ID" in message
                                for name, _, message in issues))
            files.callingCards = "gamemodes/zombiesim/tests/static_data/calling_card_aliases.json"
            registry, report = static.Build(static, files)
            self.assertIsNotNone(registry, self.messages(report.errors))
            self.assertEqual(registry.callingCards.aliases.background_old, "background_default")
        finally:
            fixture.close()


if __name__ == "__main__":
    unittest.main()
