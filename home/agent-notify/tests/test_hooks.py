import importlib.machinery
import importlib.util
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.local/lib/agent-notify'))
from agentnotify import tmux, usage

loader = importlib.machinery.SourceFileLoader('notify_test', str(ROOT / '.local/bin/agent-notify'))
spec = importlib.util.spec_from_loader(loader.name, loader)
hooks = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = hooks
loader.exec_module(hooks)


def pane(n, path='/work/project', session=''):
    return dict(id=f'%{n}', agent='codex', cmd='codex', path=path, state='waiting',
                instance=f'boot:{n}:10', session=session, generation='', prompt=f'prompt{n}')


class HookTests(unittest.TestCase):
    def setUp(self):
        self.panes = [pane(1, session='s1')]
        for p in [patch.object(tmux, 'panes', side_effect=lambda: self.panes),
                  patch.object(tmux, 'server', return_value='server'),
                  patch.object(tmux, 'screen', return_value='npm test\n❯ 1. Yes\n  2. No'),
                  patch.object(usage, 'footer', return_value='')]:
            p.start()
            self.addCleanup(p.stop)

    def test_shared_server_pane_environment_cannot_override_correct_working_directory(self):
        self.panes.append(pane(2, path='/work/other'))
        with patch.dict(os.environ, TMUX_PANE='%2'):
            self.assertEqual(hooks.codex_panes('/work/project', 's1'), ['%1'])

    def test_two_sessions_in_same_directory_require_a_matching_session_id(self):
        self.panes.append(pane(2, session='s2'))
        self.assertEqual(hooks.codex_panes('/work/project', 's2'), ['%2'])
        self.assertEqual(hooks.codex_panes('/work/project', 'unknown'), [])

    def test_completion_has_controls_and_full_conversation_identity(self):
        alert = hooks.Alert('codex', 'done', 'project', 'Finished.', {}, panes=['%1'])
        _, buttons, route = hooks.compose(alert)
        self.assertEqual(route['instance'], 'boot:1:10')
        self.assertEqual(route['session'], 's1')
        self.assertEqual(route['prompt'], 'prompt1')
        actions = [b['callback_data'] for row in buttons for b in row]
        self.assertIn('ctl:continue', actions)
        self.assertIn('sessions', actions)

    def test_delayed_alert_never_routes_to_replacement_process(self):
        old = tmux.identity(self.panes[0])
        self.panes[0]['instance'] = 'replacement'
        alert = hooks.Alert('codex', 'done', 'project', 'Old result', {}, panes=['%1'], origin=old)
        _, buttons, route = hooks.compose(alert)
        self.assertIsNone(route)
        self.assertIsNone(buttons)

    def test_replaced_prompt_is_not_reported_as_still_waiting_on_old_request(self):
        old = tmux.identity(self.panes[0])
        self.panes[0]['prompt'] = 'replacement'
        alert = hooks.Alert('codex', 'approval', 'project', 'Run?', {}, panes=['%1'], origin=old)
        self.assertFalse(hooks.still_waiting(alert))
        _, buttons, route = hooks.compose(alert)
        self.assertIsNone(route)
        self.assertIsNone(buttons)

    def test_dry_permission_hook_does_not_write_pending_files(self):
        with patch.object(hooks, 'DRY', True), patch.object(hooks, 'save_pending') as save, \
                patch.object(tmux, 'tmux') as terminal, patch.dict(os.environ, TMUX_PANE='%1'):
            hooks.claude(dict(hook_event_name='PermissionRequest', session_id='s1'))
        save.assert_not_called()
        terminal.assert_not_called()


if __name__ == '__main__':
    unittest.main()
