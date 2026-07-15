"""Makes `import app` work from tests/test_app.py - see catalog/conftest.py
for why this is needed (app.py is a flat script, not a package)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
