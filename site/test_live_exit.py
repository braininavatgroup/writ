"""Guard the actual live/release-recovery boundary; retire with those commands."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CURL = r'''import hashlib,json,os,sys,urllib.parse
from pathlib import Path
args=sys.argv[1:];url=args[-1];scenario=os.environ['SCENARIO'];log=Path(os.environ['CALL_LOG'])
old=log.read_text().splitlines() if log.exists() else []
with log.open('a') as f:f.write(url+'\n')
u=urllib.parse.urlsplit(url);root=Path(os.environ['WRIT_FIXTURE_ROOT']);status=200;ctype='application/octet-stream';body=b'fixture asset'
if scenario=='down' or (scenario=='metadata-down' and u.hostname=='api.github.com'):sys.exit(7)
tagfile=Path(os.environ['FIXTURE_TAG_FILE']);tag=tagfile.read_text() if tagfile.exists() else 'v9.9'
version=tag.removeprefix('v');dmg=b'koly'+bytes(508)
if u.hostname=='api.github.com':
 body=json.dumps({'tag_name':tag} if u.path.endswith('/releases/latest') else {'full_name':'braininavatgroup/writ'}).encode();ctype='application/json'
elif u.path.endswith('/appcast.json'):
 ctype='application/json';body=json.dumps({'version':version,'build':1,'url':f'https://github.com/braininavatgroup/writ/releases/download/{tag}/Writ-{version}.dmg','sha256':hashlib.sha256(dmg).hexdigest(),'notes':'fixture'}).encode()
 if scenario=='bad-json':body=b'null'
 if scenario=='metadata-down':status=404;body=b'not found'
elif u.hostname=='github.com' and u.path.endswith('.dmg'):body=dmg
elif u.hostname=='writ.braininavat.dance':
 source=root/'site/public'/u.path.lstrip('/')
 if u.path.endswith('/'):source=source/'index.html'
 if source.is_file():body=source.read_bytes();ctype='text/html' if source.suffix=='.html' else 'text/css'
 if u.path=='/site.css' and u.query.startswith('live='):
  count=sum(urllib.parse.urlsplit(x).path=='/site.css' and urllib.parse.urlsplit(x).query.startswith('live=') for x in old)
  if scenario in ('wrong','flip','many-wrong','legacy-override','long-settle') or (scenario=='recover' and count==0):body=b'wrong stylesheet'
  if scenario=='flip' and count==1:sys.exit(7)
 if scenario=='many-wrong' and u.path=='/privacy/' and u.query.startswith('live='):body=b'<title>wrong</title>'
out=Path(args[args.index('-o')+1]);out.write_bytes(body)
fmt=args[args.index('-w')+1];sys.stdout.write(str(status)+((' '+ctype) if '%{content_type}' in fmt else ''))
'''
GH = r'''import os,sys
from pathlib import Path
with open(os.environ['GH_LOG'],'a') as f:f.write(' '.join(sys.argv[1:])+'\n')
assert sys.argv[1:3]==['release','edit']
if os.environ['SCENARIO']=='promotion-fail':sys.exit(3)
if '--latest=true' in sys.argv:Path(os.environ['FIXTURE_TAG_FILE']).write_text(sys.argv[3])
'''


class LiveExitTest(unittest.TestCase):
    def fixture(self, directory, scenario):
        directory = Path(directory)
        bindir = directory / 'bin'
        bindir.mkdir()
        for name, body in [('curl', CURL), ('gh', GH), ('sleep', "import os,sys\nwith open(os.environ['SLEEP_LOG'],'a') as f:f.write(' '.join(sys.argv[1:])+'\\n')\n")]:
            command = bindir / name
            command.write_text(f'#!{sys.executable}\n' + body)
            command.chmod(0o755)
        return {'PATH': str(bindir) + os.pathsep + os.environ['PATH'], 'HOME': str(directory),
                'SCENARIO': scenario, 'WRIT_FIXTURE_ROOT': str(ROOT),
                'CALL_LOG': str(directory / 'curl.log'), 'GH_LOG': str(directory / 'gh.log'),
                'SLEEP_LOG': str(directory / 'sleep.log'), 'FIXTURE_TAG_FILE': str(directory / 'tag')}

    def test_actual_cli_contract_and_bounded_fresh_retry(self):
        for scenario, expected in [('pass', 0), ('wrong', 1), ('down', 3), ('flip', 3),
                                   ('bad-json', 1), ('metadata-down', 3), ('many-wrong', 1),
                                   ('missing-map', 3), ('invalid-settle', 3),
                                   ('legacy-override', 1), ('long-settle', 1), ('recover', 0)]:
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as directory:
                env = self.fixture(directory, scenario)
                if scenario == 'missing-map':
                    env['WRIT_FEATURE_MAP'] = str(Path(directory) / 'absent.json')
                if scenario == 'invalid-settle':
                    env['LIVE_SETTLE_SECONDS'] = '9000'
                if scenario == 'long-settle':
                    env['LIVE_SETTLE_SECONDS'] = '350'
                if scenario == 'legacy-override':
                    env['LIVE_ATTEMPTS'] = '99'
                result = subprocess.run(['bash', 'tools/live', 'site'], cwd=ROOT, env=env,
                                        capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                calls = Path(env['CALL_LOG']).read_text().splitlines() if Path(env['CALL_LOG']).exists() else []
                if scenario in ('wrong', 'flip', 'many-wrong', 'legacy-override', 'long-settle', 'recover'):
                    self.assertEqual(sum('/site.css?live=' in x for x in calls), 2)
                    self.assertEqual(Path(env['SLEEP_LOG']).read_text().splitlines(), ['350' if scenario=='long-settle' else '15'])
                if scenario in ('missing-map', 'invalid-settle'):
                    self.assertEqual(calls, [], 'missing local input must not start production probes')
                self.assertFalse(Path(env['GH_LOG']).exists(), 'live must never invoke the release writer')

    def test_actual_release_caller_does_not_restore_for_unavailable_observation(self):
        for scenario, expected, writes in [('pass', 0, 2), ('wrong', 1, 5), ('down', 3, 2), ('promotion-fail', 3, 1)]:
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as directory:
                env = self.fixture(directory, scenario)
                result = subprocess.run(['bash', 'tools/promote_release.sh', 'v9.9', 'v8.8'],
                                        cwd=ROOT, env=env, capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                self.assertEqual(len(Path(env['GH_LOG']).read_text().splitlines()), writes)
                if scenario == 'down':
                    self.assertNotIn('restoring the previous', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
