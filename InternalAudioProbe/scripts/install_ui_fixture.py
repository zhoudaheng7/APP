"""Install only a CI-generated synthetic recording into this job's iPhone Simulator."""
from pathlib import Path
import shutil
import sys

documents = Path(sys.argv[1]).resolve()
assert '/CoreSimulator/' in documents.as_posix() and documents.name == 'Documents'
source = Path('dist/ui-fixture').resolve()
assert source.is_dir()
destination = documents / 'Recordings'
destination.mkdir(parents=True, exist_ok=True)
for session in source.iterdir():
    if session.is_dir():
        shutil.copytree(session, destination / session.name, dirs_exist_ok=True)
