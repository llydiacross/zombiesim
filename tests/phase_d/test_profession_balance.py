"""Exercise profession rules and character persistence with isolated GLua fixtures."""

import json
import sqlite3
import unittest
import zlib
from pathlib import Path

from tests.glua.harness import FixtureRunner


ROOT = Path(__file__).resolve().parents[2]
DEFINITIONS = ROOT / "content" / "data_static" / "profession_definitions.json"
SOURCES = [
    "tests/phase_d/profession_fixture.lua",
    "gamemode/utils/sql.lua",
    "gamemode/sh_characters.lua",
    "gamemode/sh_calling_cards.lua",
    "gamemode/sh_static_data.lua",
    "gamemode/sh_professions.lua",
    "gamemode/sh_player.lua",
    "gamemode/sh_items.lua",
    "gamemode/sv_characters.lua",
    "gamemode/cl_player.lua",
    "gamemode/sv_professions.lua",
]
LEGACY_BONUSES = {
    "Civilian": {},
    "Capitalist": {},
    "Farmer": {"Farming": 3, "Endurance": 1},
    "Doctor": {"Medicine": 3, "Intelligence": 1},
    "Mechanic": {"Mechanics": 3, "WeaponRepairing": 1},
    "Hunter": {"Shotguns": 2, "Agility": 1},
    "Scavenger": {"Agility": 2, "Endurance": 1},
    "Chef": {"Farming": 1, "Endurance": 2},
    "PoliceOfficer": {"Endurance": 2, "Strength": 1, "Rifles": 1},
    "ArmySoldier": {"MachineGuns": 2, "Strength": 2, "Endurance": 1},
    "Scientist": {"Intelligence": 3},
}


class ProfessionDataTests(unittest.TestCase):
    def test_exact_legacy_rules_and_new_budget(self):
        definitions = json.loads(DEFINITIONS.read_text(encoding="utf-8"))
        professions = definitions["professions"]
        self.assertEqual(definitions["professionVersion"], 2)
        self.assertEqual(set(professions), set(LEGACY_BONUSES))
        for job, legacy in LEGACY_BONUSES.items():
            with self.subTest(job=job):
                self.assertEqual(professions[job]["legacyStatBonuses"], legacy)
                current = professions[job].get("statBonuses", {})
                self.assertLessEqual(sum(current.values()), 10)
                self.assertTrue(all(1 <= value <= 5 for value in current.values()))
                if job not in {"Civilian", "Capitalist"}:
                    self.assertEqual(sum(current.values()), 10)
                    self.assertGreater(sum(current.values()), sum(legacy.values()))
        self.assertEqual(professions["Civilian"].get("statBonuses", {}), {})
        self.assertEqual(professions["Capitalist"].get("statBonuses", {}), {})
        self.assertEqual(professions["Capitalist"]["playerLootBonuses"], {"lootCashBundles": 0.25})
        self.assertEqual(professions["PoliceOfficer"]["statBonuses"], {
            "Pistols": 3, "Shotguns": 2, "Rifles": 2, "Endurance": 2, "Strength": 1
        })
        self.assertEqual(professions["ArmySoldier"]["statBonuses"], {
            "MachineGuns": 2, "Rifles": 2, "Pistols": 1, "Shotguns": 1,
            "Strength": 2, "Endurance": 2
        })


class ProfessionFixture:
    def __init__(self):
        self.connection = sqlite3.connect(":memory:", isolation_level=None)
        self.runner = FixtureRunner(ROOT, SOURCES)
        self.lua = self.runner.lua
        self.globals = self.lua.globals()
        self.engine = self.runner.load("tests/phase_d/profession_fixture.lua")
        self.last_error = None
        self.fail_statement = None
        self.sql = self.lua.table()
        self.sql.Query = self.query
        self.sql.QueryValue = self.query_value
        self.sql.TableExists = self.table_exists
        self.sql.LastError = lambda: self.last_error
        self.sql.SQLStr = lambda value: "'" + str(value).replace("'", "''") + "'"
        self.globals.sql = self.sql
        self.globals.file = self.lua.table_from({"Read": self.read_file, "Exists": self.exists_file})
        self.globals.util.JSONToTable = self.json_to_table
        self.globals.util.TableToJSON = self.table_to_json
        self.globals.util.CRC = lambda value: str(zlib.crc32(str(value).encode("utf-8")))
        for source in SOURCES[1:]:
            self.runner.load(source)
        self.weapon_refresh = self.globals.ZM_Items.RefreshEquippedWeaponSkills
        self.globals.ZM_Items.RefreshEquippedWeaponSkills = self.lua.eval(
            "function(_, target) target.weaponRefreshes = (target.weaponRefreshes or 0) + 1 end"
        )

    def close(self):
        self.connection.close()

    def to_lua(self, value):
        if isinstance(value, dict):
            return self.lua.table_from({key: self.to_lua(item) for key, item in value.items()})
        if isinstance(value, list):
            return self.lua.table_from([self.to_lua(item) for item in value])
        return value

    def from_lua(self, value):
        if not hasattr(value, "items"):
            return value
        entries = list(value.items())
        keys = [key for key, _ in entries]
        if keys and all(isinstance(key, int) for key in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [self.from_lua(value[index]) for index in range(1, len(keys) + 1)]
        return {str(key): self.from_lua(item) for key, item in entries}

    def json_to_table(self, text):
        try:
            return self.to_lua(json.loads(str(text)))
        except (ValueError, TypeError):
            return None

    def table_to_json(self, value, *_):
        return json.dumps(self.from_lua(value), separators=(",", ":"))

    @staticmethod
    def read_file(path, realm):
        if realm != "GAME":
            raise AssertionError(f"Unexpected file realm: {realm}")
        virtual = str(path).replace("\\", "/")
        if virtual.startswith("data_static/"):
            resolved = ROOT / "content" / Path(virtual)
        elif virtual.startswith("gamemodes/zombiesim/tests/static_data/"):
            resolved = ROOT / "tests" / "static_data" / virtual.rsplit("/", 1)[1]
        else:
            raise AssertionError(f"Unexpected fixture read: {virtual}")
        return resolved.read_text(encoding="utf-8-sig") if resolved.is_file() else None

    @staticmethod
    def exists_file(path, realm):
        if realm != "GAME":
            raise AssertionError(f"Unexpected file realm: {realm}")
        virtual = str(path).replace("\\", "/")
        if not virtual.startswith("materials/scoreboard/"):
            raise AssertionError(f"Unexpected fixture existence check: {virtual}")
        return (ROOT / "content" / Path(virtual)).is_file()

    def query(self, statement):
        statement = str(statement)
        if self.fail_statement and self.fail_statement in statement:
            self.last_error = "injected SQL failure"
            return False
        try:
            cursor = self.connection.execute(statement)
        except sqlite3.Error as error:
            self.last_error = str(error)
            return False
        self.last_error = None
        if cursor.description is None:
            return None
        rows = cursor.fetchall()
        if not rows:
            return None
        result = self.lua.table()
        for index, row in enumerate(rows, 1):
            record = self.lua.table()
            for column, value in zip(cursor.description, row):
                if value is not None:
                    record[column[0]] = str(value)
            result[index] = record
        return result

    def query_value(self, statement):
        result = self.query(statement)
        if result is False or result is None:
            return result
        return next(iter(result[1].values()))

    def table_exists(self, name):
        return self.connection.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", (str(name),)
        ).fetchone() is not None

    def build_registry(self, professions=None):
        static = self.globals.ZM_StaticData
        files = self.globals.table.Copy(static.Files)
        if professions:
            files.professions = "gamemodes/zombiesim/tests/static_data/" + professions
        return static.Build(static, files)

    def prepare_registry(self):
        registry, report = self.build_registry()
        if registry is None:
            errors = [(issue["file"], issue["path"], issue["message"]) for issue in report.errors.values()]
            raise AssertionError(f"Static data fixture failed: {errors}")
        self.globals.ZM_StaticData.Registry = registry
        return registry

    def legacy_schema(self):
        self.connection.executescript(
            """
            CREATE TABLE characters (
                steamid TEXT NOT NULL, profile TEXT NOT NULL, slot INTEGER NOT NULL,
                characterId TEXT NOT NULL UNIQUE, name TEXT NOT NULL, model TEXT, skin INTEGER,
                bodygroups TEXT, playerColour TEXT, job TEXT NOT NULL DEFAULT 'Civilian',
                originCellX INTEGER, originCellY INTEGER, originLatitude REAL, originLongitude REAL,
                createdAt INTEGER NOT NULL, lastPlayedAt INTEGER NOT NULL DEFAULT 0,
                appearanceRequired INTEGER NOT NULL DEFAULT 1, PRIMARY KEY (steamid, profile, slot)
            );
            CREATE TABLE zm_schema_version (version INTEGER PRIMARY KEY, appliedAt INTEGER NOT NULL);
            INSERT INTO zm_schema_version VALUES (1, 123);
            INSERT INTO characters (steamid, profile, slot, characterId, name, job, createdAt)
            VALUES ('STEAM_0:1:111', 'preview', 1, 'legacy-preview', 'Existing', 'PoliceOfficer', 12);
            INSERT INTO characters (steamid, profile, slot, characterId, name, job, createdAt)
            VALUES ('STEAM_0:1:111', 'city', 1, 'legacy-city', 'City Existing', 'Doctor', 13);
            """
        )

    def create_player_tables(self):
        for create in (self.globals.ZM_CreatePlayerAttributesTable, self.globals.ZM_CreatePlayerDataTable):
            result = create()
            succeeded = result[0] if isinstance(result, tuple) else result
            assert succeeded is True, f"Could not create fixture player tables: {result}"

    def create_character(self, profile, slot=2):
        payload = self.to_lua({
            "name": "Fresh Survivor", "job": "Police",
            "appearance": {
                "model": "models/player/group01/male_01.mdl", "skin": 0,
                "bodygroups": {}, "playerColour": [1, 1, 1]
            },
            "attributes": {"Strength": 10}
        })
        return self.globals.ZM_CharacterService.CreateOwned(
            self.globals.ZM_CharacterService, "STEAM_0:1:111", profile, slot, payload
        )

    def activate(self, profile, slot):
        self.connection.execute(
            "INSERT OR REPLACE INTO active_characters (steamid, profile, slot, selectedAt) VALUES (?, ?, ?, 1)",
            ("STEAM_0:1:111", profile, slot),
        )
        self.globals.ZM_World.ActiveProfile = profile
        return self.globals.ZM_TestPlayer("STEAM_0:1:111", profile)


class ProfessionIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.fixture = ProfessionFixture()
        self.addCleanup(self.fixture.close)
        self.fixture.prepare_registry()
        self.fixture.create_player_tables()
        self.fixture.legacy_schema()
        self.characters = self.fixture.globals.ZM_CharacterService

    def migrate(self):
        result = self.characters.Migrate(self.characters)
        if isinstance(result, tuple) and result[0] is True:
            return True
        return result

    def test_static_validator_checks_legacy_and_current_budgets(self):
        registry, report = self.fixture.build_registry("bad_professions.json")
        self.assertIsNone(registry)
        issues = {(issue["path"], issue["message"]) for issue in report.errors.values()}
        self.assertTrue(any(path == "professions.Farmer.statBonuses" and "at most 10" in message
                            for path, message in issues))
        self.assertTrue(any(path == "professions.Farmer.legacyStatBonuses" and "at most 6" in message
                            for path, message in issues))
        self.assertTrue(any(path == "professions.Doctor.legacyStatBonuses" and "required" in message
                            for path, message in issues))

    def test_migration_preserves_rows_and_is_idempotent(self):
        before = self.fixture.connection.execute("SELECT * FROM characters ORDER BY profile").fetchall()
        self.assertTrue(self.migrate())
        after = self.fixture.connection.execute("SELECT * FROM characters ORDER BY profile").fetchall()
        self.assertEqual([row[:-1] for row in after], before)
        self.assertEqual([row[-1] for row in after], [1, 1])
        self.assertTrue(self.migrate())
        self.assertEqual(self.fixture.connection.execute("SELECT * FROM characters ORDER BY profile").fetchall(), after)

    def test_migration_failure_leaves_original_rows_intact(self):
        before = self.fixture.connection.execute("SELECT * FROM characters ORDER BY profile").fetchall()
        self.fixture.fail_statement = "ALTER TABLE characters ADD COLUMN"
        succeeded, error = self.migrate()
        self.assertFalse(succeeded)
        self.assertIn("injected SQL failure", error)
        self.assertEqual(self.fixture.connection.execute("SELECT * FROM characters ORDER BY profile").fetchall(), before)
        self.assertNotIn("professionBonusVersion", {
            row[1] for row in self.fixture.connection.execute("PRAGMA table_info(characters)")
        })

    def test_creation_and_active_identity_keep_each_profile_ruleset(self):
        self.assertTrue(self.migrate())
        created, character_id = self.fixture.create_character("preview")
        self.assertTrue(created)
        self.assertEqual(self.fixture.connection.execute(
            "SELECT profile, slot, professionBonusVersion FROM characters WHERE characterId = ?", (character_id,)
        ).fetchone(), ("preview", 2, 2))
        self.assertEqual(self.fixture.connection.execute(
            "SELECT Strength, Pistols FROM player_attributes WHERE steamid = ?", (character_id,)
        ).fetchone(), (10, 0))
        target = self.fixture.activate("preview", 2)
        self.assertEqual(target.GetCharacterKey(target), character_id)
        target.Attributes = self.fixture.globals.ZM_GetPlayerAttributes(character_id, "preview")
        target.Job = self.fixture.globals.ZM_GetPlayerData(character_id, "preview").Job
        self.assertEqual(target.GetProfessionBonusVersion(target), 2)
        self.assertEqual(target.GetStat(target, "Pistols"), 3)
        legacy = self.fixture.activate("city", 1)
        self.assertEqual(legacy.GetCharacterKey(legacy), "legacy-city")
        self.assertEqual(legacy.GetProfessionBonusVersion(legacy), 1)
        legacy.profile = "preview"
        self.assertEqual(legacy.GetCharacterKey(legacy), character_id)
        self.assertEqual(legacy.GetProfessionBonusVersion(legacy), 2)
        reconnected = self.fixture.activate("preview", 2)
        self.assertEqual(reconnected.GetCharacterKey(reconnected), character_id)
        self.assertEqual(reconnected.GetProfessionBonusVersion(reconnected), 2)

    def test_invalid_stored_version_is_not_treated_as_legacy(self):
        self.assertTrue(self.migrate())
        self.fixture.connection.execute(
            "UPDATE characters SET professionBonusVersion = 99 WHERE characterId = 'legacy-preview'"
        )
        target = self.fixture.activate("preview", 1)
        character_id, error = target.GetCharacterKey(target)
        self.assertIsNone(character_id)
        self.assertIn("Invalid stored profession bonus version", error)

    def test_client_snapshot_and_remote_network_choose_the_correct_rules(self):
        rules = self.fixture.globals.ZM_Professions
        target = self.fixture.globals.ZM_TestPlayer("STEAM_0:1:111", "preview")
        target.Attributes = self.fixture.to_lua({"Medicine": 2})
        target.SetPlayerData(target, self.fixture.to_lua({"Job": "Doctor", "ProfessionBonusVersion": 2}))
        self.assertEqual(target.GetStat(target, "Medicine"), 6)
        remote = self.fixture.globals.ZM_TestPlayer("STEAM_0:1:222", "preview")
        remote.Attributes = self.fixture.to_lua({"Medicine": 2})
        remote.nw["Job"] = "Doctor"
        remote.nw["ZM_ProfessionBonusVersion"] = 1
        self.assertEqual(remote.GetStat(remote, "Medicine"), 5)
        remote.nw["ZM_ProfessionBonusVersion"] = 2
        self.assertEqual(remote.GetStat(remote, "Medicine"), 6)
        self.assertFalse(rules.IsValidBonusVersion(rules, 99))
        target.SetPlayerData(target, self.fixture.to_lua({"Job": "Doctor", "ProfessionBonusVersion": 99}))
        self.assertEqual(target.GetProfessionBonusVersion(target), 2)
        self.assertIn("Invalid replicated profession bonus version", self.fixture.engine.errors[1])
        target.SetPlayerData(target, self.fixture.to_lua({"Job": "PoliceOfficer"}))
        self.assertEqual(target.GetProfessionBonusVersion(target), 2)
        self.assertEqual(target.GetJobRole(target), "Doctor")
        self.assertIn("Invalid replicated profession bonus version", self.fixture.engine.errors[2])

    def test_job_changes_refresh_skills_and_failed_save_preserves_previous_job(self):
        self.assertTrue(self.migrate())
        created, character_id = self.fixture.create_character("preview")
        self.assertTrue(created)
        target = self.fixture.activate("preview", 2)
        self.assertEqual(target.GetCharacterKey(target), character_id)
        target.Attributes = self.fixture.globals.ZM_GetPlayerAttributes(character_id, "preview")
        target.Job = self.fixture.globals.ZM_GetPlayerData(character_id, "preview").Job
        target.ZM_PersistentStateLoaded = True
        target.Stamina = 500
        self.fixture.globals.ZM_Items.RefreshEquippedWeaponSkills = self.fixture.weapon_refresh
        weapon = self.fixture.globals.ZM_TestEquipWeapon(target, "weaponHandgun9mm")
        self.fixture.weapon_refresh(self.fixture.globals.ZM_Items, target)
        self.assertAlmostEqual(weapon.nw["ZM_WeaponSkillAccuracyScale"], 0.91)
        self.assertAlmostEqual(weapon.nw["ZM_WeaponSkillReloadScale"], 0.94)
        service = self.fixture.globals.ZM_ProfessionService
        changed, _ = service.SetJob(service, target, "Doctor")
        self.assertTrue(changed)
        self.assertEqual(target.GetStat(target, "Medicine"), 4)
        self.assertEqual(target.GetProfessionBonusVersion(target), 2)
        accuracy, reload = self.fixture.globals.ZM_Items.GetWeaponSkillScales(
            self.fixture.globals.ZM_Items, target, self.fixture.to_lua({"weaponFamily": "Pistols"})
        )
        self.assertEqual((accuracy, reload), (1, 1))
        self.assertEqual(target.Stamina, target.GetMaxStamina(target))
        self.assertEqual(weapon.nw["ZM_WeaponSkillAccuracyScale"], 1)
        self.assertEqual(weapon.nw["ZM_WeaponSkillReloadScale"], 1)
        self.assertEqual(target.movementRefreshes, 1)
        self.assertEqual(target.nw["Job"], "Doctor")
        self.assertEqual(self.fixture.connection.execute(
            "SELECT Job FROM player_data WHERE steamid = ?", (character_id,)
        ).fetchone()[0], "Doctor")
        self.fixture.fail_statement = "INSERT OR REPLACE INTO player_data"
        changed, error = service.SetJob(service, target, "Police")
        self.assertFalse(changed)
        self.assertIn("injected SQL failure", error)
        self.assertEqual(target.Job, "Doctor")
        self.assertEqual(target.nw["Job"], "Doctor")
        self.assertEqual(weapon.nw["ZM_WeaponSkillAccuracyScale"], 1)
        self.assertEqual(weapon.nw["ZM_WeaponSkillReloadScale"], 1)
        self.assertEqual(target.movementRefreshes, 1)

    def test_existing_survivor_keeps_legacy_rules_through_job_changes(self):
        self.assertTrue(self.migrate())
        self.fixture.connection.execute(
            "INSERT INTO player_data (steamid, profile, Job, Stamina) VALUES ('legacy-city', 'city', 'Doctor', 100)"
        )
        target = self.fixture.activate("city", 1)
        self.assertEqual(target.GetCharacterKey(target), "legacy-city")
        target.Attributes = self.fixture.to_lua({})
        target.Job = "Doctor"
        target.Stamina = 100
        target.ZM_PersistentStateLoaded = True
        service = self.fixture.globals.ZM_ProfessionService
        self.assertTrue(service.SetJob(service, target, "Police")[0])
        self.assertEqual(target.GetProfessionBonusVersion(target), 1)
        self.assertEqual(target.GetStat(target, "Pistols"), 0)
        self.assertEqual(target.GetStat(target, "Rifles"), 1)
        accuracy, reload = self.fixture.globals.ZM_Items.GetWeaponSkillScales(
            self.fixture.globals.ZM_Items, target, self.fixture.to_lua({"weaponFamily": "Rifles"})
        )
        self.assertAlmostEqual(accuracy, 0.97)
        self.assertAlmostEqual(reload, 0.98)
        self.assertTrue(service.SetJob(service, target, "Doctor")[0])
        self.assertEqual(target.GetStat(target, "Medicine"), 3)
        reconnected = self.fixture.activate("city", 1)
        self.assertEqual(reconnected.GetCharacterKey(reconnected), "legacy-city")
        self.assertEqual(reconnected.GetProfessionBonusVersion(reconnected), 1)


if __name__ == "__main__":
    unittest.main()
