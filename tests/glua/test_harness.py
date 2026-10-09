"""Regression tests for the shared offline fixture loader."""

from contextlib import redirect_stdout
import io
from pathlib import Path
import tempfile
import unittest

from glua.harness import FixtureRunner, compare, lua_source, plain


class HarnessTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", encoding="utf-8", newline="") as output:
            output.write(text)
        return path

    def test_comment_translation_preserves_strings_and_lines(self):
        source = (
            '// GLua comment\r\nlocal url = "https://example.test/a" // end\r\n'
            "local escaped = 'it\\'s // text'\n"
            'local long = [=[// text "quoted"]=]\n'
            "--[==[// original long comment]==]\n"
            "-- existing // Lua comment\n// final comment"
        )
        expected = source.replace("// GLua comment", "-- GLua comment").replace(
            "// end\r\n", "-- end\r\n"
        ).replace("// final comment", "-- final comment")
        self.assertEqual(lua_source(self.write("source.lua", source)), expected)

    def test_multiline_strings_and_unterminated_source_are_not_rewritten(self):
        source = 'local value = [[// first\n// second]]\nlocal broken = "// unfinished'
        self.assertEqual(lua_source(self.write("source.lua", source)), source)

    def test_comparison_identifies_field_and_rejects_bool_number(self):
        compare({"count": 3, "value": 0.1}, {"count": 3.0, "value": 0.1 + 1e-12})
        with self.assertRaisesRegex(AssertionError, "snapshot.count"):
            compare({"count": 1}, {"count": True})
        with self.assertRaisesRegex(AssertionError, "changed fields"):
            compare({"count": 1}, {})
        with self.assertRaises(AssertionError):
            compare(float("nan"), float("nan"))

    def test_loader_rejects_nonallowlisted_and_escaping_paths(self):
        self.write("fixture.lua", "return 42")
        names = ["fixture.lua", "../outside.lua", "/absolute.lua", "C:/outside.lua", "dir\\fixture.lua"]
        runner = FixtureRunner(self.root, names)
        self.assertEqual(runner.load("fixture.lua"), 42)
        for name in names[1:] + ["unknown.lua"]:
            with self.subTest(name=name), self.assertRaises(ValueError):
                runner.load(name)
        with self.assertRaises(FileNotFoundError):
            FixtureRunner(self.root, ["missing.lua"]).load("missing.lua")

    def test_lua_errors_include_source_name(self):
        self.write("broken.lua", 'error("intentional fixture failure")')
        runner = FixtureRunner(self.root, ["broken.lua"])
        with self.assertRaisesRegex(Exception, "broken.lua.*intentional fixture failure"):
            runner.load("broken.lua")

    def test_unsupported_glua_syntax_is_not_silently_translated(self):
        self.write("glua.lua", "return 1 != 2")
        runner = FixtureRunner(self.root, ["glua.lua"])
        with self.assertRaisesRegex(Exception, "glua.lua"):
            runner.load("glua.lua")

    def test_fixture_runtimes_do_not_share_globals(self):
        self.write("fixture.lua", "counter = (counter or 0) + 1; return counter")
        first = FixtureRunner(self.root, ["fixture.lua"])
        second = FixtureRunner(self.root, ["fixture.lua"])
        self.assertEqual(first.load("fixture.lua"), 1)
        self.assertEqual(first.load("fixture.lua"), 2)
        self.assertEqual(second.load("fixture.lua"), 1)

    def test_inconsistent_summary_cannot_report_success(self):
        runner = FixtureRunner(self.root, [])
        suite = runner.lua.eval("""{
            Run = function()
                return { passed = 1, failed = 0, cases = {
                    { name = "misreported", passed = false, failures = { "failure" } }
                } }
            end
        }""")
        with self.assertRaisesRegex(AssertionError, "inconsistent"):
            runner.run(suite, "Misreported")

    def test_real_suite_reports_failures_and_rejects_empty_suite(self):
        root = Path(__file__).resolve().parents[2] / "gamemode"
        runner = FixtureRunner(root, ["utils/test_harness.lua"])
        runner.load("utils/test_harness.lua")
        suite = runner.lua.eval("{ Run = function() return ZM_TestHarness.NewSuite():Run() end }")
        with self.assertRaisesRegex(AssertionError, "empty"):
            runner.run(suite, "Empty")
        suite = runner.lua.eval("""{
            Run = function()
                local suite = ZM_TestHarness.NewSuite()
                suite:Add("success", function(check) check(true, "ok") end)
                suite:Add("failure", function(check) check(false, "expected failure") end)
                suite:Add("error", function() error("expected exception") end)
                return suite:Run()
            end
        }""")
        result = plain(suite.Run())
        self.assertEqual((result["passed"], result["failed"]), (1, 2))
        output = io.StringIO()
        with redirect_stdout(output), self.assertRaisesRegex(AssertionError, "regressions failed"):
            runner.run(suite, "Intentional failures")
        self.assertIn("PASS success", output.getvalue())
        self.assertIn("FAIL failure", output.getvalue())
        self.assertIn("expected exception", output.getvalue())


if __name__ == "__main__":
    unittest.main()
