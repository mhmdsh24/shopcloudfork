"""
Makes `import app` work from tests/test_app.py.

app.py is a flat script, not a package (no __init__.py), and pytest's
default import mode only adds the *test file's own* directory to
sys.path - not its parent. Without this, `import app` inside
tests/test_app.py would fail with ModuleNotFoundError even though
app.py is right there one directory up.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
