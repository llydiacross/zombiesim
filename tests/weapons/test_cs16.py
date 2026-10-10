import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct
import sys
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from glua.harness import FixtureRunner


ROOT = Path(__file__).resolve().parents[2]
CONTENT = ROOT / "content"
EXPECTED = {
    "ak47", "aug", "awp", "deagle", "elite", "famas", "fiveseven", "g3sg1",
    "galil", "glock18", "m249", "m3", "m4a1", "mac10", "mp5", "p228", "p90",
    "scout", "sg550", "sg552", "tmp", "ump45", "usp", "xm1014",
}


def model_materials(path):
    data = path.read_bytes()
    count, offset, directory_count, directory_offset = struct.unpack_from("<4i", data, 204)
    directories = []
    for index in range(directory_count):
        start = struct.unpack_from("<i", data, directory_offset + index * 4)[0]
        directories.append(data[start:data.index(b"\0", start)].decode().replace("\\", "/"))
    names = []
    for index in range(count):
        start = offset + index * 64
        start += struct.unpack_from("<i", data, start)[0]
        names.append(data[start:data.index(b"\0", start)].decode())
    return [next((CONTENT / "materials" / (directory + name + ".vmt")
                  for directory in directories
                  if (CONTENT / "materials" / (directory + name + ".vmt")).is_file()), None)
            for name in names]


class CS16Tests(unittest.TestCase):
    def test_expanded_arsenal_and_exact_rare_weights(self):
        items = json.loads((CONTENT / "data_static" / "item_definitions.json").read_text())["items"]
        groups = json.loads((CONTENT / "data_static" / "loot.json").read_text())["groups"]
        weapons = {key: item for key, item in items.items() if item.get("type") == "bullet_weapon"}
        self.assertEqual(len(weapons), 55)
        self.assertEqual(len([item for item in weapons.values()
                              if item.get("viewModel", "").startswith("models/weapons/cstrike/")]), 24)
        self.assertEqual(len([item for item in weapons.values()
                              if item.get("cssFamily", "").startswith("hl2_")]), 5)
        normal_weights = {}
        for group, definition in groups.items():
            if group != "lootGenericCs16Weapons":
                normal_weights.update(definition.get("items", {}))
        overrides = {"usp": "weaponUsp9mm", "glock18": "weaponAutoPistol9mm", "m3": "weaponShotgunM3"}
        for item_id, weights in groups["lootGenericCs16Weapons"]["items"].items():
            with self.subTest(weapon=item_id):
                item = items[item_id]
                self.assertEqual(item["rarity"], "very_rare")
                family = item["cssFamily"].removeprefix("cs16_")
                normal_id = overrides.get(family) or next(
                    key for key, candidate in weapons.items() if candidate.get("cssFamily") == family)
                normal = normal_weights[normal_id]
                for danger in (0, 0.25, 0.5, 0.75, 1):
                    rare_weight = weights["minWeight"] * (1 - danger) + weights["maxWeight"] * danger
                    normal_weight = normal["minWeight"] * (1 - danger) + normal["maxWeight"] * danger
                    self.assertAlmostEqual(rare_weight, normal_weight / 100)
        for ammo in ("ammo357", "ammoPulse", "ammoBolts"):
            self.assertIn(ammo, groups["lootGenericAmmunition"]["items"])

    def test_animation_adapter_and_large_clip(self):
        runner = FixtureRunner(ROOT, [
            "entities/weapons/weapon_zn_base.lua",
            "entities/weapons/weapon_zn_base_hitscan.lua",
            "entities/weapons/weapon_zn_base_cs16.lua",
        ])
        runner.lua.execute("""
            SERVER=false CLIENT=false
            function AddCSLuaFile() end
            function DEFINE_BASECLASS() end
            function IsValid(value) return type(value)=="table" and value.valid~=false end
            function ErrorNoHalt(message) error(message) end
            function CurTime() return 10 end
            ACT_VM_PRIMARYATTACK=1 ACT_VM_RELOAD=2 ACT_VM_DRAW=3 ACT_VM_IDLE=4
            math.Clamp=function(value, low, high) return math.min(high, math.max(low,value)) end
            math.Round=function(value) return math.floor(value+0.5) end
            string.StartWith=function(value, prefix) return value:sub(1,#prefix)==prefix end
            SWEP={Primary={},Secondary={}}
        """)
        runner.load("entities/weapons/weapon_zn_base.lua")
        runner.lua.execute("WeaponBase=SWEP; SWEP=setmetatable({Primary={}}, {__index=WeaponBase})")
        runner.load("entities/weapons/weapon_zn_base_hitscan.lua")
        runner.lua.execute("""
            Hitscan=SWEP
            function Hitscan:GetScale() return self.instanceScale or 1 end
            function Hitscan:GetScaledDamage(value) return value*self:GetScale("DamageScale") end
            function Hitscan:GetScaledDelay(value) return value*self:GetScale("SpeedScale") end
            BaseClass=Hitscan
            SWEP=setmetatable({Primary={}}, {__index=Hitscan})
        """)
        runner.load("entities/weapons/weapon_zn_base_cs16.lua")
        runner.lua.execute("""
            local model={calls={}}
            local ids={idle1=0,draw=1,shoot1=2,reload=3,shoot_left1=4,shoot_right1=5}
            function model:LookupSequence(name) return ids[name] or -1 end
            function model:SendViewModelMatchingSequence(sequence) self.calls[#self.calls+1]=sequence end
            function model:SequenceDuration(sequence) return 0.5 end
            local owner={}
            function owner:GetViewModel() return model end
            local weapon=setmetatable({Primary={ClipSize=256}, BaseClipSize=100, clip=29}, {__index=SWEP})
            function weapon:GetOwner() return owner end
            function weapon:Clip1() return self.clip end
            function weapon:IsSafeZoneHolstered() return false end
            function weapon:UpdateSafeZoneHolster() return false end
            function weapon:IsReloading() return false end
            function weapon:GetReloadFinishTime() return 0 end
            assert(weapon:GetMaxClip()==120)
            assert(weapon:GetScaledDamage(20)==25)
            assert(weapon:GetScale("RangeScale")==1.2)
            assert(math.abs(weapon:GetScaledDelay(0.1)-0.1/1.15)<1e-9)
            assert(math.abs(weapon:GetScale("ReloadScale")-1/1.15)<1e-9)
            weapon.instanceScale=1.5
            assert(weapon:GetScaledDamage(20)==37.5)
            assert(weapon:GetMaxClip()==180)
            weapon.instanceScale=1
            assert(weapon:Deploy()==true and model.calls[1]==1)
            assert(weapon.NextIdleAt==10.5)
            weapon:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
            assert(model.calls[2]==2)
            weapon:SendWeaponAnim(ACT_VM_RELOAD)
            assert(model.calls[3]==3)
            weapon.DualPistols=true
            weapon:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
            assert(model.calls[4]==5)
            weapon.clip=28
            weapon:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
            assert(model.calls[5]==4)
            weapon.NextIdleAt=9
            weapon:Think()
            assert(model.calls[6]==0)
            assert(weapon:FireAnimationEvent(nil,nil,5004,"OldAK47.Clipin")==true)
            assert(weapon:FireAnimationEvent(nil,nil,0,"EjectBrass_556 2 100")==true)
            ZM_WeaponEffects={AnimationEvents={[5001]=true}}
            assert(weapon:FireAnimationEvent(nil,nil,5001,"1")==true)
            assert(weapon:FireAnimationEvent(nil,nil,3005,"")==nil)
            weapon.DualPistols=false
            weapon.FireSequence="missing"
            assert(not pcall(weapon.SendWeaponAnim,weapon,ACT_VM_PRIMARYATTACK))
        """)

    def test_assets_and_namespaces(self):
        manifest = json.loads((CONTENT / "data_static" / "imported_assets.json").read_text())
        for entry in manifest["files"]:
            if "cs16/" not in entry["path"] and entry["path"] != "data_static/asset_credits/cs16_original.txt":
                continue
            with self.subTest(asset=entry["path"]):
                path = CONTENT / entry["path"]
                data = path.read_bytes()
                self.assertEqual(len(data), entry["bytes"])
                self.assertEqual(hashlib.sha256(data).hexdigest(), entry["sha256"])
                self.assertTrue(entry["path"].startswith((
                    "models/cs16/", "models/weapons/cs16/", "materials/weapons/cs16/",
                    "sound/zombiesim/cs16/", "data_static/asset_credits/",
                )))

    def test_firearm_contract(self):
        items = json.loads((CONTENT / "data_static" / "item_definitions.json").read_text())["items"]
        firearms = {key: item for key, item in items.items() if key.startswith("weaponCs16")}
        self.assertEqual(len(firearms), 24)
        self.assertEqual({item["weaponClass"].removeprefix("weapon_zn_cs16_")
                          for item in firearms.values()}, EXPECTED)
        loot = json.loads((CONTENT / "data_static" / "loot.json").read_text())["groups"]
        offers = json.loads((CONTENT / "data_static" / "trade_definitions.json").read_text())["traders"]["quartermaster"]["offers"]
        self.assertIn("lootGenericCs16Weapons", loot["lootGenericWeapons"]["include"])
        self.assertEqual(set(loot["lootGenericCs16Weapons"]["items"]), set(firearms))
        self.assertLessEqual(len(offers), 32)
        self.assertFalse(any(offer["item"] in firearms for offer in offers))
        base = (ROOT / "entities" / "weapons" / "weapon_zn_base_cs16.lua").read_text()
        for item_id, item in firearms.items():
            with self.subTest(weapon=item_id):
                source = (ROOT / "entities" / "weapons" / (item["weaponClass"] + ".lua")).read_text()
                self.assertIn('SWEP.Base = "weapon_zn_base_cs16"', source)
                self.assertIn(f'SWEP.ViewModel = "{item["viewModel"]}"', source)
                self.assertIn(f'SWEP.WorldModel = "{item["worldModel"]}"', source)
                self.assertEqual("SWEP.Primary.Automatic = true" in source,
                                 item["firingMode"] == "automatic")
                self.assertIn(item["ammoId"], items)
                for key in ("viewModel", "worldModel", "iconModel"):
                    model = CONTENT / item[key]
                    self.assertTrue(model.is_file(), key)
                    for extension in (".vvd", ".dx90.vtx"):
                        self.assertTrue(model.with_suffix(extension).is_file())
                    self.assertTrue(all(model_materials(model)), f"Missing model materials: {key}")
                model = (CONTENT / item["viewModel"]).read_bytes()
                count, offset = struct.unpack_from("<ii", model, 188)
                sequences = set()
                for index in range(count):
                    start = offset + index * 212
                    start += struct.unpack_from("<i", model, start + 4)[0]
                    sequences.add(model[start:model.index(b"\0", start)].decode())
                for key in ("IdleSequence", "DrawSequence", "FireSequence", "ReloadSequence"):
                    match = re.search(rf'SWEP\.{key} = "([^"]+)"', source)
                    if match is None:
                        match = re.search(rf'SWEP\.{key} = "([^"]+)"', base)
                    self.assertIn(match[1], sequences)
                for sound in re.findall(r'SWEP\.\w*Sound = "([^"]+)"', source):
                    self.assertTrue((CONTENT / "sound" / sound).is_file(), sound)
                if item["weaponClass"].endswith("_m249"):
                    self.assertIn("SWEP.Primary.ClipSize = 256", source)
                    self.assertIn("SWEP.BaseClipSize = 100", source)

    def test_material_texture_closure(self):
        for path in (CONTENT / "materials" / "weapons" / "cs16").rglob("*.vmt"):
            source = path.read_text(errors="replace")
            for texture in re.findall(
                    r'"\$(?:basetexture|bumpmap|detail|envmapmask)"\s+"([^"]+)"',
                    source, re.IGNORECASE):
                with self.subTest(material=path.name, texture=texture):
                    self.assertTrue((CONTENT / "materials" / (texture.replace("\\", "/") + ".vtf")).is_file())

    def test_gma_integrity(self):
        spec = importlib.util.spec_from_file_location("asset_importer", ROOT / "bin" / "import_assets.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        archive = ROOT / "assets" / "models" / "gmod_addons_2657591603_1637211535.zip"
        with self.assertRaisesRegex(ValueError, "approved"):
            module.read_gma(b"wrong archive")
        if not archive.exists():
            self.skipTest("Source archive removed; retained payload integrity is covered by ownership tests")
        with zipfile.ZipFile(archive) as source:
            data = source.read("2657591603.1637211535.gma")
        _, _, _, files = module.read_gma(data)
        self.assertEqual(len(files), 1830)
        with self.assertRaisesRegex(ValueError, "approved"):
            module.read_gma(data[:-1])


if __name__ == "__main__":
    unittest.main()
