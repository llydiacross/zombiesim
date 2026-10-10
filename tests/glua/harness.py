"""Execute allowlisted Lua fixtures and report ZM_TestHarness results offline."""

import math
from pathlib import Path, PurePosixPath
import re


def lua_source(path):
    """Translate GLua line comments only; preserve strings and Lua comments."""
    with Path(path).open(encoding="utf-8", newline="") as source:
        text = source.read()
    result = []
    index = 0
    while index < len(text):
        start = index
        if text[index] in "'\"":
            quote = text[index]
            index += 1
            while index < len(text):
                if text[index] == "\\":
                    index += 2
                elif text[index] == quote:
                    index += 1
                    break
                else:
                    index += 1
        else:
            comment = text.startswith(("--", "//"), index)
            bracket_at = index + 2 if text.startswith("--", index) else index
            bracket = re.match(r"\[(=*)\[", text[bracket_at:]) if text[bracket_at:bracket_at + 1] == "[" else None
            if bracket:
                closing = "]" + bracket.group(1) + "]"
                end = text.find(closing, bracket_at + bracket.end())
                index = len(text) if end < 0 else end + len(closing)
            elif comment:
                end = text.find("\n", index)
                index = len(text) if end < 0 else end
                result.append("--" + text[start + 2:index])
                continue
            else:
                index += 1
        result.append(text[start:index])
    return "".join(result)


def plain(value):
    """Convert acyclic Lua result tables to Python dictionaries."""
    if hasattr(value, "items"):
        return {key: plain(item) for key, item in value.items()}
    return value


def compare(expected, actual, path="snapshot"):
    """Fail with the field path, even when Python runs with optimization."""
    if isinstance(expected, dict) and isinstance(actual, dict):
        if expected.keys() != actual.keys():
            raise AssertionError(f"{path}: changed fields {expected.keys() ^ actual.keys()}")
        for key in expected:
            compare(expected[key], actual[key], f"{path}.{key}")
    elif isinstance(expected, (int, float)) and not isinstance(expected, bool):
        if isinstance(actual, bool) or not isinstance(actual, (int, float)) or not math.isclose(
            expected, actual, rel_tol=1e-9, abs_tol=1e-9
        ):
            raise AssertionError(f"{path}: {expected} != {actual}")
    elif type(expected) is not type(actual) or expected != actual:
        raise AssertionError(f"{path}: {expected!r} != {actual!r}")


class FixtureRunner:
    """One LuaJIT runtime per runner; all source loads require an exact allowlist."""

    def __init__(self, source_root, allowed_files):
        try:
            from lupa.luajit21 import LuaRuntime
        except ImportError as error:
            raise RuntimeError(
                "Offline fixtures require lupa: python -m pip install -r tests\\glua\\requirements.txt"
            ) from error
        self.source_root = Path(source_root).resolve()
        self.allowed_files = frozenset(allowed_files)
        self.lua = LuaRuntime(unpack_returned_tuples=True)

    def compile(self, name):
        """Compile an allowlisted chunk for explicit fixture-environment injection."""
        relative = PurePosixPath(name)
        if (
            name not in self.allowed_files
            or "\\" in name
            or relative.is_absolute()
            or ".." in relative.parts
            or ":" in name
        ):
            raise ValueError(f"Unexpected fixture source: {name}")
        path = (self.source_root / name).resolve()
        if not path.is_relative_to(self.source_root):
            raise ValueError(f"Fixture source escapes root: {name}")
        return self.lua.eval("function(source, name) return assert(loadstring(source, name)) end")(
            lua_source(path), f"@{name}"
        )

    def load(self, name):
        return self.compile(name)()

    def register(self, suite_file, engine_file):
        self.load("utils/test_harness.lua")
        register = self.load(suite_file)
        register(self.load(engine_file), self.load)

    def run(self, suite, label):
        summary = plain(suite.Run())
        cases = summary["cases"]
        passed = sum(result["passed"] is True for result in cases.values())
        if (
            not cases
            or summary["passed"] != passed
            or summary["failed"] != len(cases) - passed
            or any(
                type(result["passed"]) is not bool
                or result["passed"] != (len(result["failures"]) == 0)
                for result in cases.values()
            )
        ):
            raise AssertionError(f"{label}: empty or inconsistent suite result")
        for index in sorted(cases):
            result = cases[index]
            print(f"{'PASS' if result['passed'] else 'FAIL'} {result['name']}")
            for failure in result["failures"].values():
                print(f"  {failure}")
        print(f"{label}: {summary['passed']} passed, {summary['failed']} failed.")
        if summary["failed"] != 0:
            raise AssertionError(f"{label} regressions failed")
        return summary
