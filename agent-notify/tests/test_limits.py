import importlib.machinery
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.local/lib/agent-notify'))
from agentnotify import limits

loader = importlib.machinery.SourceFileLoader('watcher', str(ROOT / '.local/bin/limit-alerts'))
spec = importlib.util.spec_from_loader(loader.name, loader)
watcher = importlib.util.module_from_spec(spec)
loader.exec_module(watcher)


class ResetTests(unittest.TestCase):
    def setUp(self):
        self.now = 10000
        self.state = {}
        self.current = limits.Usage('codex', [limits.Window('5h', '5h', 95, 10060),
                                             limits.Window('weekly', 'weekly', 19, 90000)])
        self.patches = [patch.object(watcher, 'PROVIDERS', ('codex',)),
                        patch.dict(limits.FETCH, codex=lambda: self.current),
                        patch.object(limits, 'codex_recent_windows', return_value=[]),
                        patch.object(watcher.time, 'time', side_effect=lambda: self.now),
                        patch.object(watcher, 'notify', return_value=True)]
        for p in self.patches:
            p.start()
            self.addCleanup(p.stop)

    def tick(self):
        watcher.tick(self.state)

    def test_95_percent_window_announces_reset_once(self):
        self.tick()
        watcher.notify.assert_not_called()
        self.now = 10061
        self.tick()
        self.assertIn('Codex is back', watcher.notify.call_args.args[1])
        self.tick()
        self.assertEqual(watcher.notify.call_count, 1)

    def test_rollover_preserves_previous_reset(self):
        self.tick()
        self.now = 10061
        self.current.windows[0] = limits.Window('5h', '5h', 1, 28000)
        self.tick()
        self.assertEqual(watcher.notify.call_count, 1)
        self.assertTrue(self.state['providers']['codex']['watched'])

    def test_failed_send_retries_across_restart_and_late_cutoff(self):
        self.tick()
        self.now = 10061
        watcher.notify.return_value = False
        self.tick()
        self.state = json.loads(json.dumps(self.state))
        self.now += watcher.LATE_FREE + 1
        watcher.notify.return_value = True
        self.tick()
        self.tick()
        self.assertEqual(watcher.notify.call_count, 2)

    def test_api_failure_does_not_announce_or_forget(self):
        self.tick()
        self.now = 10061
        old = self.current
        self.current = limits.Usage('codex', error='HTTP 429')
        self.tick()
        watcher.notify.assert_not_called()
        self.current = old
        self.tick()
        self.assertEqual(watcher.notify.call_count, 1)

    def test_weekly_block_suppresses_back_message(self):
        self.current.windows[1].percent = 100
        self.tick()
        watcher.notify.reset_mock()
        self.now = 10061
        self.tick()
        watcher.notify.assert_not_called()
        self.now = 90001
        self.current.windows[1].percent = 0
        self.current.windows[0].percent = 0
        self.tick()
        self.assertEqual(watcher.notify.call_count, 1)
        self.assertIn('weekly limit reset', watcher.notify.call_args.args[1])

    def test_recover_reset_from_before_watcher_startup(self):
        limits.codex_recent_windows.return_value = [limits.Window('5h', '5h', 95, 9990)]
        self.current.windows[0].percent = 0
        self.tick()
        self.tick()
        self.assertEqual(watcher.notify.call_count, 1)

    def test_simultaneous_windows_deduplicated_on_later_polls(self):
        self.current.windows[1].resets_at = 10080
        self.tick()
        self.now = 10081
        self.tick()
        self.tick()
        self.assertEqual(watcher.notify.call_count, 2)

    def test_empty_windows_never_trigger_recovery(self):
        self.tick()
        self.now = 10061
        self.current.windows = []
        self.tick()
        watcher.notify.assert_not_called()

    def test_near_reset_polls_fast_below_100_percent(self):
        self.tick()
        self.assertEqual(watcher.sleep_for(self.state, 120), 20)

    def test_legacy_blocked_state_retries_failed_send(self):
        self.state = {'providers': {'codex': {'blocked': {'label': '5h', 'reset': 9990}}}}
        self.current.windows[0].percent = 0
        watcher.notify.side_effect = [False, True]
        self.tick()
        self.tick()
        self.tick()
        self.assertEqual(watcher.notify.call_count, 2)


class HistoryTests(unittest.TestCase):
    def test_only_recent_used_codex_windows_are_recovered(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            folder = home / '.codex/sessions/2026/11/06'
            folder.mkdir(parents=True)
            def event(reset, percent, bucket='codex'):
                return json.dumps({'payload': {'type': 'token_count', 'rate_limits': {
                    'limit_id': bucket, 'primary': {'used_percent': percent, 'resets_at': reset}}}})
            (folder / 'test.jsonl').write_text('\n'.join([
                event(9990, 95), event(9995, 0), event(9999, 100, 'other'), event(1, 100)]))
            with patch.object(limits, 'HOME', home):
                windows = limits.codex_recent_windows(10000, 7200)
            self.assertEqual([(w.key, w.percent, w.resets_at) for w in windows], [('5h', 95, 9990)])


if __name__ == '__main__':
    unittest.main()
