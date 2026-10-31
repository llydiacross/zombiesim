"""Exercise the production attribute migration against isolated SQLite databases."""

import sqlite3
import unittest
from pathlib import Path

from tests.glua.harness import FixtureRunner


ROOT = Path(__file__).resolve().parents[2]
SQL_SOURCE = "gamemode/utils/sql.lua"
LEGACY_FIELDS = [
    "Strength", "Agility", "Intelligence", "Endurance", "MachineGuns",
    "Shotguns", "Snipers", "WeaponCrafting", "ArmorCrafting", "Medicine",
    "Farming", "WeaponRepairing", "ArmorRepairing", "Mechanics",
    "Revision", "UpdatedAt",
]


class AttributeMigrationTests(unittest.TestCase):
    def setUp(self):
        self.connection = sqlite3.connect(":memory:")
        self.addCleanup(self.connection.close)
        self.runner = FixtureRunner(ROOT, [SQL_SOURCE])
        self.lua = self.runner.lua
        self.last_error = None
        self.fail_copy = False
        self.fail_commit = False
        self.fail_rollback = False
        sql_api = self.lua.table()
        sql_api.Query = self.query
        sql_api.TableExists = self.table_exists
        sql_api.LastError = lambda: self.last_error
        self.lua.globals().sql = sql_api
        self.runner.load(SQL_SOURCE)

    def query(self, statement):
        statement = str(statement)
        if self.fail_copy and statement.startswith("INSERT INTO player_attributes "):
            self.last_error = "injected copy failure"
            return False
        if self.fail_commit and statement == "COMMIT":
            self.last_error = "injected commit failure"
            return False
        if self.fail_rollback and statement == "ROLLBACK":
            self.last_error = "injected rollback failure"
            return False
        try:
            cursor = self.connection.execute(statement)
        except sqlite3.Error as error:
            self.last_error = str(error)
            return False

        self.last_error = None
        if cursor.description is None:
            return None
        result = self.lua.table()
        for index, row in enumerate(cursor.fetchall(), 1):
            record = self.lua.table()
            for column, value in zip(cursor.description, row):
                record[column[0]] = value
            result[index] = record
        return result

    def table_exists(self, name):
        row = self.connection.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
            (str(name),),
        ).fetchone()
        return row is not None

    def create_legacy_table(self, with_profile=True, with_rifles=False):
        fields = list(LEGACY_FIELDS)
        if with_rifles:
            fields.insert(fields.index("Snipers"), "Rifles")
        columns = ["steamid TEXT NOT NULL"]
        if with_profile:
            columns.append("profile TEXT NOT NULL")
        columns.extend(f"{field} INTEGER" for field in fields)
        key = "steamid, profile" if with_profile else "steamid"
        self.connection.execute(
            "CREATE TABLE player_attributes (" + ", ".join(columns)
            + ", PRIMARY KEY (" + key + "))"
        )

    def insert_legacy_row(self, steamid, profile=None, **values):
        fields = ["steamid"]
        row = [steamid]
        if self.table_exists("player_attributes") and self.connection.execute(
            "PRAGMA table_info(player_attributes)"
        ).fetchall()[1][1] == "profile":
            fields.append("profile")
            row.append(profile or "city")
        for field in LEGACY_FIELDS:
            if field in values:
                fields.append(field)
                row.append(values[field])
        placeholders = ", ".join("?" for _ in row)
        self.connection.execute(
            "INSERT INTO player_attributes (" + ", ".join(fields) + ") VALUES ("
            + placeholders + ")",
            row,
        )
        self.connection.commit()

    def migrate(self):
        return self.lua.globals().ZM_CreatePlayerAttributesTable()

    def test_profiled_sniper_rows_transfer_once_and_new_fields_default_to_zero(self):
        self.create_legacy_table()
        self.insert_legacy_row(
            "steam-a", "city", Strength=4, Snipers=3, Revision=7, UpdatedAt=1234
        )
        self.insert_legacy_row(
            "steam-a", "preview", Strength=2, Snipers=1, Revision=5, UpdatedAt=4321
        )

        self.assertEqual(self.migrate(), True)
        rows = self.connection.execute(
            "SELECT profile, Strength, Pistols, Rifles, Explosives, Revision, UpdatedAt "
            "FROM player_attributes ORDER BY profile"
        ).fetchall()
        self.assertEqual(rows, [
            ("city", 4, 0, 3, 0, 7, 1234),
            ("preview", 2, 0, 1, 0, 5, 4321),
        ])
        self.assertNotIn(
            "Snipers",
            {row[1] for row in self.connection.execute("PRAGMA table_info(player_attributes)")},
        )
        self.assertEqual(self.migrate(), True)

    def test_existing_rifles_value_wins_when_legacy_snipers_also_exists(self):
        self.create_legacy_table(with_rifles=True)
        self.insert_legacy_row("steam-a", "city", Snipers=8, Revision=1, UpdatedAt=2)
        self.connection.execute(
            "UPDATE player_attributes SET Rifles = 2 WHERE steamid = 'steam-a'"
        )
        self.connection.commit()

        self.assertEqual(self.migrate(), True)
        rifles = self.connection.execute(
            "SELECT Rifles FROM player_attributes WHERE steamid = 'steam-a'"
        ).fetchone()[0]
        self.assertEqual(rifles, 2)

    def test_unprofiled_legacy_rows_migrate_to_city(self):
        self.create_legacy_table(with_profile=False)
        self.insert_legacy_row("steam-a", Snipers=6, Revision=3, UpdatedAt=9)

        self.assertEqual(self.migrate(), True)
        row = self.connection.execute(
            "SELECT profile, Rifles, Pistols, Explosives FROM player_attributes"
        ).fetchone()
        self.assertEqual(row, ("city", 6, 0, 0))

    def test_copy_failure_rolls_back_the_original_table(self):
        self.create_legacy_table()
        self.insert_legacy_row("steam-a", "preview", Snipers=4, Revision=2, UpdatedAt=8)
        self.fail_copy = True

        succeeded, error = self.migrate()
        self.assertFalse(succeeded)
        self.assertIn("injected copy failure", error)
        self.assertTrue(self.table_exists("player_attributes"))
        self.assertFalse(self.table_exists("player_attributes_legacy"))
        row = self.connection.execute(
            "SELECT profile, Snipers FROM player_attributes"
        ).fetchone()
        self.assertEqual(row, ("preview", 4))

    def test_commit_failure_rolls_back_and_reports_failure(self):
        self.create_legacy_table()
        self.insert_legacy_row("steam-a", "city", Snipers=4, Revision=2, UpdatedAt=8)
        self.fail_commit = True

        succeeded, error = self.migrate()
        self.assertFalse(succeeded)
        self.assertIn("injected commit failure", error)
        self.assertTrue(self.table_exists("player_attributes"))
        self.assertFalse(self.table_exists("player_attributes_legacy"))
        self.assertEqual(
            self.connection.execute("SELECT Snipers FROM player_attributes").fetchone()[0],
            4,
        )

    def test_rollback_failure_is_reported_explicitly(self):
        self.create_legacy_table()
        self.insert_legacy_row("steam-a", "city", Snipers=4, Revision=2, UpdatedAt=8)
        self.fail_copy = True
        self.fail_rollback = True

        succeeded, error = self.migrate()
        self.assertFalse(succeeded)
        self.assertIn("injected copy failure", error)
        self.assertIn("rollback failed: injected rollback failure", error)


if __name__ == "__main__":
    unittest.main()
