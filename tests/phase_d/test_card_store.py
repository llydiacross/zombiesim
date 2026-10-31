"""Exercise card ownership and trader transactions against isolated SQLite."""

import unittest

from tests.phase_d.test_profession_balance import ProfessionFixture


class CallingCardStoreTests(unittest.TestCase):
    def setUp(self):
        self.fixture = ProfessionFixture()
        self.addCleanup(self.fixture.close)
        self.globals = self.fixture.globals
        self.lua = self.fixture.lua
        self.registry = self.fixture.prepare_registry()
        self.fixture.runner.allowed_files |= frozenset({
            "gamemode/sv_credits.lua",
            "gamemode/sv_calling_cards.lua",
            "gamemode/sv_trading.lua",
        })
        self.globals.ZM_Util.CharacterKeyFor = self.lua.eval(
            "function(target) return target:GetCharacterKey() end"
        )
        self.globals.ZM_Util.ProfileFor = self.lua.eval(
            "function(target) return target.ZM_InventoryProfile or target.profile end"
        )
        self.globals.ZM_Util.IsPlayerEntity = self.lua.eval("function() return false end")
        self.lua.execute("""
            function ZM_InventoryService:CanAccessStash(target) return target.inDen end
            function ZM_InventoryService:CurrentDenId(target) return "fixture-den" end
            ZM_SafeZones = {}
            function ZM_SafeZones:GetEntranceCell(id) assert(id == "fixture-den") return {} end
            function ZM_World:GetDangerIntensity(cell) return 0 end
            ZM_DenNpcs = {}
            function ZM_DenNpcs:Resolve(npc) return { trader = npc.trader } end
            function CurTime() return 100 end
        """)
        for source in ("gamemode/sv_credits.lua", "gamemode/sv_calling_cards.lua", "gamemode/sv_trading.lua"):
            self.fixture.runner.load(source)
        for create in (self.globals.ZM_CreateCreditTables, self.globals.ZM_CreateCallingCardTables,
                       self.globals.ZM_CreateTradeTables):
            result = create()
            self.assertTrue(result[0] if isinstance(result, tuple) else result, result)
        self.cards = self.globals.ZM_CallingCardService
        self.trade = self.globals.ZM_TradeService
        self.credits = self.globals.ZM_CreditService
        catalogue = self.registry.callingCards
        for card in (
            {"id": "background_test", "category": "background", "name": "Test",
             "material": "scoreboard/backgrounds/test_background.png", "shopCredits": 100, "questReward": True},
            {"id": "detail_reward", "category": "detail", "name": "Reward",
             "material": "scoreboard/details/reward_details.png", "questReward": True},
            {"id": "detail_shop", "category": "detail", "name": "Shop only",
             "material": "scoreboard/details/shop_details.png", "shopCredits": 100, "questReward": False},
        ):
            catalogue.byId[card["id"]] = self.fixture.to_lua(card)
        catalogue.aliases.background_old = "background_test"
        self.player = self.new_player("STEAM_0:1:111", "character-one", "preview")
        self.npc = self.lua.eval("""function()
            return { valid = true, ZM_IsDenNpc = true, trader = "general",
                GetPos = function() return {} end }
        end""")()

    def new_player(self, account, character, profile):
        target = self.globals.ZM_TestPlayer(account, profile)
        target.fixtureCharacter = character
        target.ZM_PersistentStateLoaded = True
        target.ZM_Inventory = self.lua.table()
        target.inDen = True
        target.near = True
        target.GetCharacterKey = self.lua.eval("function(self) return self.fixtureCharacter end")
        target.Alive = self.lua.eval("function() return true end")
        target.GetPos = self.lua.eval("""function(self)
            return { DistToSqr = function() return self.near and 0 or 1000000 end }
        end""")
        return target

    def snapshot(self, target=None):
        result = self.cards.Snapshot(self.cards, target or self.player)
        if isinstance(result, tuple):
            self.fail(f"Snapshot failed: {result}")
        return result

    def fund(self, amount=300):
        ok, message = self.credits.Grant(self.credits, self.player, amount, "fixture")
        self.assertTrue(ok, message)

    def buy(self, request_id, price=100, card_id="background_test", target=None):
        request = self.fixture.to_lua({"id": card_id, "price": price, "requestId": request_id})
        return self.trade.BuyCallingCard(self.trade, target or self.player, self.npc, request)

    def test_defaults_are_free_and_load_without_writing_rows(self):
        snapshot = self.snapshot()
        self.assertTrue(snapshot.owned.background_default)
        self.assertTrue(snapshot.owned.detail_default)
        self.assertIsNone(snapshot.owned.background_test)
        self.assertEqual(snapshot.selection.background, "background_default")
        self.assertEqual(snapshot.selection.detail, "detail_default")
        self.assertTrue(self.cards.Load(self.cards, self.player))
        self.assertEqual(self.player.nw.ZM_CallingCardBackground, "background_default")
        self.assertEqual(self.fixture.connection.execute(
            "SELECT count(*) FROM calling_card_selections"
        ).fetchone()[0], 0)

    def test_rewards_are_shared_per_account_and_profile_but_selection_is_per_survivor(self):
        self.assertTrue(self.cards.GrantReward(self.cards, self.player, "background_old", "quest fixture")[0])
        self.assertTrue(self.cards.GrantReward(self.cards, self.player, "background_test", "repeat")[0])
        second = self.new_player("STEAM_0:1:111", "character-two", "preview")
        city = self.new_player("STEAM_0:1:111", "city-character", "city")
        stranger = self.new_player("STEAM_0:1:222", "stranger", "preview")
        self.assertTrue(self.snapshot(second).owned.background_test)
        self.assertIsNone(self.snapshot(city).owned.background_test)
        self.assertIsNone(self.snapshot(stranger).owned.background_test)
        self.assertTrue(self.cards.Select(self.cards, self.player, "background", "background_test")[0])
        self.assertEqual(self.snapshot(self.player).selection.background, "background_test")
        self.assertEqual(self.snapshot(second).selection.background, "background_default")
        reconnected = self.new_player("STEAM_0:1:111", "character-one", "preview")
        self.assertTrue(self.cards.Load(self.cards, reconnected))
        self.assertEqual(reconnected.nw.ZM_CallingCardBackground, "background_test")
        self.assertEqual(self.fixture.connection.execute(
            "SELECT count(*) FROM calling_card_unlocks"
        ).fetchone()[0], 1)

    def test_selection_rejects_locked_wrong_category_and_unavailable_cards(self):
        for category, card in (("background", "background_test"), ("detail", "background_default"),
                               ("background", "background_absent"), ("invalid", "background_default")):
            with self.subTest(category=category, card=card):
                ok, _ = self.cards.Select(self.cards, self.player, category, card)
                self.assertFalse(ok)
        self.assertEqual(self.fixture.connection.execute(
            "SELECT count(*) FROM calling_card_selections"
        ).fetchone()[0], 0)

    def test_missing_and_renamed_designs_preserve_persisted_ids(self):
        self.assertTrue(self.cards.GrantReward(self.cards, self.player, "background_test", "fixture")[0])
        self.assertTrue(self.cards.Select(self.cards, self.player, "background", "background_test")[0])
        catalogue = self.registry.callingCards
        entry = catalogue.byId.background_test
        catalogue.byId.background_test = None
        catalogue.aliases.background_old = None
        missing = self.snapshot()
        card, status = self.globals.ZM_CallingCards.Resolve(
            catalogue, missing.selection.background, "background"
        )
        self.assertEqual((card.id, status), ("background_default", "missing"))
        self.assertEqual(missing.selection.background, "background_test")
        catalogue.byId.background_new = self.fixture.to_lua({
            "id": "background_new", "category": "background", "name": "Renamed",
            "material": entry.material, "shopCredits": 100, "questReward": True,
        })
        catalogue.aliases.background_test = "background_new"
        renamed = self.snapshot()
        self.assertTrue(renamed.owned.background_new)
        card, status = self.globals.ZM_CallingCards.Resolve(catalogue, renamed.selection.background, "background")
        self.assertEqual((card.id, status), ("background_new", "alias"))
        self.assertEqual(self.fixture.connection.execute(
            "SELECT cardId FROM calling_card_unlocks"
        ).fetchone()[0], "background_test")

    def test_trader_purchase_is_atomic_replay_safe_and_shared(self):
        self.fund()
        self.assertTrue(self.buy("request-one")[0])
        self.assertEqual(self.player.Credits, 200)
        self.assertEqual(self.globals.ZM_GetPlayerCredits("character-one", "preview"), 200)
        second = self.new_player("STEAM_0:1:111", "character-two", "preview")
        second.Credits = 300
        self.assertTrue(self.snapshot(second).owned.background_test)
        self.assertFalse(self.buy("request-one")[0])
        self.assertFalse(self.buy("another", target=second)[0])
        self.assertEqual(self.player.Credits, 200)
        self.assertEqual(self.fixture.connection.execute(
            "SELECT count(*), sum(credits) FROM trade_ledger"
        ).fetchone(), (1, 100))
        self.assertEqual(self.fixture.connection.execute(
            "SELECT count(*) FROM calling_card_unlocks"
        ).fetchone()[0], 1)

    def test_five_credit_purchase_cannot_be_resold(self):
        self.registry.callingCards.byId.background_test.shopCredits = 5
        self.fund(5)
        self.assertTrue(self.buy("five-credit", price=5)[0])
        self.assertEqual(self.player.Credits, 0)
        self.assertEqual(self.globals.ZM_GetPlayerCredits("character-one", "preview"), 0)
        self.assertTrue(self.snapshot().owned.background_test)
        self.assertIsNone(self.player.ZM_Inventory.backpack)

        self.trade.FindTrader = self.lua.eval("function(_, target) return target.fixtureTrader end")
        self.player.fixtureTrader = self.npc
        for ref in ("background_test", "calling_card:background_test"):
            with self.subTest(ref=ref):
                self.player.ZM_NextTradeRequestAt = None
                request = self.fixture.to_lua({
                    "action": "sell", "ref": ref, "requestId": "attempted-resale"
                })
                _, ok, message = self.trade.HandleRequest(self.trade, self.player, request)
                self.assertFalse(ok)
                self.assertEqual(message, "That item is not in your backpack.")
                self.assertTrue(self.snapshot().owned.background_test)
                self.assertEqual(self.player.Credits, 0)
        self.player.ZM_NextTradeRequestAt = None
        _, ok, message = self.trade.HandleRequest(
            self.trade, self.player, self.fixture.to_lua({"action": "sell_calling_card"})
        )
        self.assertFalse(ok)
        self.assertEqual(message, "Unknown action.")
        self.assertEqual(self.fixture.connection.execute(
            "SELECT count(*), sum(credits) FROM trade_ledger"
        ).fetchone(), (1, 5))

    def test_shop_checks_access_price_funds_and_quest_only_designs(self):
        self.fund(50)
        self.assertFalse(self.buy("poor")[0])
        self.assertFalse(self.buy("stale", price=99)[0])
        self.assertFalse(self.buy("quest-only", card_id="detail_reward")[0])
        self.player.inDen = False
        self.assertFalse(self.buy("outside-den")[0])
        self.player.inDen = True
        self.player.near = False
        self.assertFalse(self.buy("too-far")[0])
        self.assertEqual(self.player.Credits, 50)
        self.assertEqual(self.fixture.connection.execute(
            "SELECT count(*) FROM calling_card_unlocks"
        ).fetchone()[0], 0)

    def test_reward_respects_shop_only_quest_only_and_both(self):
        ok, error = self.cards.GrantReward(self.cards, self.player, "detail_shop", "quest")
        self.assertFalse(ok)
        self.assertIn("not a quest reward", error)
        self.assertTrue(self.cards.GrantReward(self.cards, self.player, "detail_reward", "quest")[0])
        self.assertTrue(self.cards.GrantReward(self.cards, self.player, "background_test", "quest")[0])
        self.assertTrue(self.snapshot().owned.detail_reward)
        self.assertTrue(self.snapshot().owned.background_test)
        self.assertIsNone(self.snapshot().owned.detail_shop)

    def test_failed_unlock_or_ledger_write_rolls_back_credits_and_ownership(self):
        self.fund()
        for statement in ("INSERT INTO calling_card_unlocks", "INSERT INTO trade_ledger"):
            with self.subTest(statement=statement):
                self.fixture.fail_statement = statement
                ok, error = self.buy("rollback")
                self.fixture.fail_statement = None
                self.assertFalse(ok)
                self.assertIn("injected SQL failure", error)
                self.assertEqual(self.player.Credits, 300)
                self.assertEqual(self.globals.ZM_GetPlayerCredits("character-one", "preview"), 300)
                self.assertEqual(self.fixture.connection.execute(
                    "SELECT count(*) FROM calling_card_unlocks"
                ).fetchone()[0], 0)
                self.assertEqual(self.fixture.connection.execute(
                    "SELECT count(*) FROM trade_ledger"
                ).fetchone()[0], 0)

    def test_reward_failure_and_bad_storage_are_reported(self):
        self.fixture.fail_statement = "INSERT INTO calling_card_unlocks"
        ok, error = self.cards.GrantReward(self.cards, self.player, "detail_reward", "quest")
        self.fixture.fail_statement = None
        self.assertFalse(ok)
        self.assertIn("injected SQL failure", error)
        self.fixture.connection.execute(
            "INSERT INTO calling_card_unlocks VALUES (?, ?, ?, ?, 1)",
            ("STEAM_0:1:111", "preview", "bad-id", "fixture"),
        )
        snapshot, error = self.cards.Snapshot(self.cards, self.player)
        self.assertIsNone(snapshot)
        self.assertIn("invalid ID", error)

    def test_native_suite_runs_against_isolated_sqlite_and_cleans_up(self):
        self.fixture.runner.allowed_files |= frozenset({
            "gamemode/utils/test_harness.lua",
            "gamemode/tests/sv_calling_card_tests.lua",
        })
        self.lua.execute("""
            function Vector(x, y, z)
                return { x = x, y = y, z = z, DistToSqr = function(self, other)
                    return (self.x - other.x)^2 + (self.y - other.y)^2 + (self.z - other.z)^2
                end }
            end
            concommand = { Add = function(name, callback)
                assert(name == "zn_test_calling_cards" and type(callback) == "function")
            end }
        """)
        self.fixture.runner.load("gamemode/utils/test_harness.lua")
        self.fixture.runner.load("gamemode/tests/sv_calling_card_tests.lua")
        summary = self.cards.RunTests(self.cards)
        failures = [
            f"{case.name}: {list(case.failures.values())}"
            for case in summary.cases.values() if not case.passed
        ]
        self.assertEqual(summary.passed, 4, failures)
        self.assertEqual(summary.failed, 0, failures)
        for table_name in (
            "calling_card_unlocks", "calling_card_selections", "player_credits", "credit_ledger", "trade_ledger"
        ):
            self.assertEqual(
                self.fixture.connection.execute(f"SELECT count(*) FROM {table_name}").fetchone()[0],
                0,
                table_name,
            )

    def test_server_wire_messages_assemble_in_the_actual_client_receiver(self):
        self.fixture.runner.allowed_files |= frozenset({
            "gamemode/cl_calling_card_state.lua",
            "gamemode/cl_calling_cards.lua",
            "gamemode/tests/fixtures/cl_calling_card_engine.lua",
        })
        catalogue = self.registry.callingCards
        for index in range(70):
            card_id = f"background_extra_{index:03d}"
            catalogue.byId[card_id] = self.fixture.to_lua({
                "id": card_id, "category": "background", "name": card_id, "questReward": True
            })
            self.fixture.connection.execute(
                "INSERT INTO calling_card_unlocks VALUES (?, ?, ?, ?, 1)",
                ("STEAM_0:1:111", "preview", card_id, "fixture"),
            )
        self.globals.ZM_Util.IsPlayerEntity = self.lua.eval("function(target) return target.valid == true end")
        self.lua.execute("""
            net.frames = {}
            function net.Start(name)
                assert(name == "ZM.CallingCardState")
                net.current = {}
            end
            function net.WriteUInt(value, bits)
                assert(type(value) == "number" and value >= 0 and value < 2^bits)
                table.insert(net.current, { kind = "uint", value = value, bits = bits })
            end
            function net.WriteBool(value)
                assert(type(value) == "boolean")
                table.insert(net.current, { kind = "bool", value = value })
            end
            function net.WriteString(value)
                assert(type(value) == "string")
                table.insert(net.current, { kind = "string", value = value })
            end
            function net.Send(target)
                assert(target.valid)
                table.insert(net.frames, net.current)
                net.current = nil
            end
        """)
        create_state = self.fixture.runner.load("gamemode/cl_calling_card_state.lua")
        create_engine = self.fixture.runner.load("gamemode/tests/fixtures/cl_calling_card_engine.lua")
        env, engine = create_engine(self.globals.ZM_CallingCards)
        engine.registry = self.lua.table_from({"callingCards": catalogue})
        initialize = self.fixture.runner.load("gamemode/cl_calling_cards.lua")
        self.lua.eval("function(f, env, create) setfenv(f, env); f(create) end")(initialize, env, create_state)
        ui = env.ZM_CallingCardUI
        ui.PendingSince, ui.PendingRequestId = 1, "expected_request"

        def send_and_deliver(request_id):
            start = len(self.globals.net.frames) + 1
            self.cards.SendState(self.cards, self.player, True, "Fixture response.", request_id)
            end = len(self.globals.net.frames)
            self.assertEqual(end - start + 1, 3)
            frames = [self.globals.net.frames[index] for index in range(start, end + 1)]
            self.assertEqual([frame[3].value for frame in frames], [3, 3, 3])
            self.assertEqual([frame[9].value for frame in frames], [32, 32, 8])
            for frame in reversed(frames):
                engine.read = frame
                engine.receivers["ZM.CallingCardState"]()
                self.assertEqual(len(engine.read), 0)

        send_and_deliver("unrelated_request")
        self.assertEqual(ui.PendingRequestId, "expected_request")
        self.assertEqual(ui.Message, None)
        send_and_deliver("expected_request")
        self.assertIsNone(ui.PendingRequestId)
        self.assertIsNone(ui.PendingSince)
        self.assertEqual(ui.Message.text, "Fixture response.")
        self.assertEqual(len(list(ui.State.owned.keys())), 72)
        self.assertTrue(ui.State.owned.background_extra_000)
        self.assertTrue(ui.State.owned.background_extra_069)

    def test_character_deletion_keeps_account_unlocks(self):
        self.assertTrue(self.cards.GrantReward(self.cards, self.player, "background_test", "fixture")[0])
        self.assertTrue(self.cards.Select(self.cards, self.player, "background", "background_test")[0])
        connection = self.fixture.connection
        for table_name in self.globals.ZM_CharacterService.StorageTables.values():
            if not self.fixture.table_exists(table_name):
                connection.execute(f"CREATE TABLE {table_name} (steamid TEXT, profile TEXT)")
        connection.executescript("""
            CREATE TABLE character_bios (characterId TEXT);
            CREATE TABLE active_characters (steamid TEXT, profile TEXT, slot INTEGER);
            CREATE TABLE characters (steamid TEXT, profile TEXT, slot INTEGER);
            INSERT INTO characters VALUES ('STEAM_0:1:111', 'preview', 1);
        """)
        record = self.fixture.to_lua({
            "steamid": "STEAM_0:1:111", "profile": "preview", "slot": 1, "characterId": "character-one"
        })
        self.assertTrue(self.globals.ZM_CharacterService.DeleteOwnedRows(
            self.globals.ZM_CharacterService, record
        ))
        self.assertEqual(connection.execute("SELECT count(*) FROM calling_card_selections").fetchone()[0], 0)
        self.assertEqual(connection.execute("SELECT count(*) FROM calling_card_unlocks").fetchone()[0], 1)


if __name__ == "__main__":
    unittest.main()
