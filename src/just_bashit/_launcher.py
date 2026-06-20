"""Thin shims that exec bundled bash scripts as console_scripts entry points."""
import os
import sys
from pathlib import Path

_BIN = Path(__file__).parent


def _exec(script: str) -> None:
    path = _BIN / script
    os.execvp("bash", ["bash", str(path)] + sys.argv[1:])


def jb() -> None:
    _exec("just-runit")


def jbx() -> None:
    _exec("just-runit")


def jb_inspect() -> None:
    _exec("inspect.sh")
