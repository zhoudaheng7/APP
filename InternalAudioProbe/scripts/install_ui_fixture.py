"""Install only a CI-generated synthetic recording into this job's iPhone Simulator."""
from pathlib import Path
import json
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
        target = destination / session.name
        shutil.copytree(session, target, dirs_exist_ok=True)
        # Exercise compatibility with the previous installed app. Only this CI
        # Simulator fixture is renamed; real recordings and the AAC contents stay untouched.
        report_path = target / 'session.json'
        report = json.loads(report_path.read_text(encoding='utf-8'))
        if len(report['segments']) == 1:
            original = target / report['segments'][0]['filename']
            original.rename(target / 'recording.m4a')
            report['segments'][0]['filename'] = 'recording.m4a'
            report_path.write_text(json.dumps(report), encoding='utf-8')
