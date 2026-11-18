import copy
import importlib.machinery
import importlib.util
import itertools
import os
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.local/lib/agent-notify'))
from agentnotify import telegram, tmux
from agentnotify.store import Store


def load_bridge():
    loader = importlib.machinery.SourceFileLoader('bridge_test', str(ROOT / '.local/bin/tg-bridge'))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    with patch.object(sys, 'argv', ['tg-bridge', 'codex']), \
            patch.object(telegram, 'config', return_value=('test-token', 123)):
        loader.exec_module(module)
    return module


bridge = load_bridge()
READY = 'A completed reply.\n›\n  gpt-6 · 90% left'
BUSY = '• Working (5s • esc to interrupt)\n›\n  gpt-6'
APPROVAL = 'Run a command?\nnpm test\n❯ 1. Yes\n  2. No'


def pane(n=1, agent='codex'):
    return dict(id=f'%{n}', cmd=agent, agent=agent, tag=agent, state='done', path=f'/work/project{n}',
                where=f'main:{n}', pid=str(100 + n), instance=f'boot:{100 + n}:10',
                session=f'session{n}', generation='')


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.panes = [pane()]
        bridge._STORE = Store(self.root / 'bridge.sqlite3')
        bridge._CONTEXT.targets = {}
        bridge.BOT = 'codex'
        bridge.TG = Mock(chat=123)
        bridge.TG.send.side_effect = itertools.count(100)
        self.patches = [patch.object(telegram, 'STATE', self.root),
                        patch.dict(os.environ, XDG_STATE_HOME=self.tmp.name),
                        patch.object(tmux, 'panes', side_effect=lambda: copy.deepcopy(self.panes)),
                        patch.object(tmux, 'server', return_value='server1'),
                        patch.object(tmux, 'screen', return_value=READY),
                        patch.object(tmux, 'checked', side_effect=self.command),
                        patch.object(tmux, 'tmux', side_effect=self.command),
                        patch.object(bridge.time, 'sleep')]
        for item in self.patches:
            item.start()
            self.addCleanup(item.stop)

    def command(self, *args, **kwargs):
        if args[0] == 'set' and args[4] in ('@agent_state', '@tg_generation'):
            target = next(p for p in self.panes if p['id'] == args[3])
            target['state' if args[4] == '@agent_state' else 'generation'] = args[-1]
        return ''

    def route(self, p=None, kind='done', mid=7, **extra):
        p = p or self.panes[0]
        telegram.remember('codex', mid, **tmux.identity(p), kind=kind, **extra)
        return telegram.route('codex', mid)

    def button(self, data, mid=7):
        return dict(id='query1', data=data, message=dict(message_id=mid,
                    chat=dict(id=123, type='private')), **{'from': {'id': 123}})

    def test_plain_message_and_both_agent_shortcuts_hold_approval(self):
        self.panes.append(pane(2, 'claude'))
        tmux.screen.return_value = APPROVAL
        for text in ('check build', '/codex check build', '/claude check build'):
            with self.subTest(text=text):
                bridge.on_message(dict(message_id=1, text=text))
        tmux.checked.assert_not_called()
        self.assertIn('waiting on a prompt', bridge.TG.send.call_args.args[0])

    def test_panel_covering_input_is_not_typed_into(self):
        tmux.screen.return_value = 'Settings\nUse Escape to close'
        with self.assertRaisesRegex(RuntimeError, 'covered by a panel'):
            bridge.on_message(dict(message_id=1, text='check build'))
        tmux.checked.assert_not_called()

    def test_old_route_rejected_after_agent_restarts_in_same_pane(self):
        self.route()
        self.panes[0]['instance'] = 'boot:201:20'
        p, _, error = bridge.pick(reply_to=7)
        self.assertIsNone(p)
        self.assertIn('ended', error)

    def test_conversation_change_and_clear_generation_invalidate_old_routes(self):
        for field in ('session', 'generation'):
            with self.subTest(field=field):
                self.panes[0] = pane()
                r = self.route()
                self.panes[0][field] = 'replacement'
                self.assertIsNone(bridge.Live().of(r))

    def test_clear_invalidates_old_alerts_and_keeps_new_session_selected(self):
        r = self.route()
        bridge.run(copy.deepcopy(self.panes[0]), '/clear', 1, r)
        self.assertIsNone(bridge.Live().of(r))
        selected, _, error = bridge.pick()
        self.assertIsNone(error)
        self.assertTrue(selected['generation'])
        self.assertIsNotNone(bridge.Live().of(telegram.route('codex', 100)))

    def test_legacy_route_and_reboot_are_rejected(self):
        self.assertIsNone(bridge.Live().of(dict(pane='%1', agent='codex', server='server1')))
        r = self.route()
        tmux.server.return_value = 'new-server'
        self.assertIsNone(bridge.Live().of(r))

    def test_unrouted_reply_never_falls_back_to_another_session(self):
        self.assertIsNotNone(bridge.pick(reply_to=999)[2])

    def test_several_sessions_require_a_choice_even_when_one_just_alerted(self):
        self.panes.append(pane(2))
        self.route(self.panes[1])
        self.assertIn('Choose one', bridge.pick()[2])

    def test_selection_survives_restart_and_other_sessions_alerting(self):
        self.panes.append(pane(2))
        bridge.storage().set('codex', 'selected:codex', tmux.identity(self.panes[0]))
        self.route(self.panes[1])
        bridge._STORE = Store(self.root / 'bridge.sqlite3')
        self.assertEqual(bridge.pick()[0]['id'], '%1')

    def test_ended_selection_does_not_silently_choose_surviving_session(self):
        bridge.pick()
        self.panes = [pane(2)]
        self.assertIn('selected session has ended', bridge.pick()[2])

    def test_explicit_cross_agent_command_rejects_conflicting_reply(self):
        self.route()
        self.panes.append(pane(2, 'claude'))
        self.assertIn('another agent', bridge.pick('claude', reply_to=7)[2])

    def test_session_button_pins_actual_destination_for_plain_messages(self):
        self.panes.append(pane(2, 'claude'))
        mid = bridge.session_picker()
        bridge.on_button(self.button('session:1', mid))
        self.assertEqual(bridge.pick()[0]['agent'], 'claude')
        self.assertEqual(bridge.pick('codex')[0]['agent'], 'codex')

    def test_old_session_picker_cannot_select_restarted_agent(self):
        mid = bridge.session_picker()
        self.panes[0]['instance'] = 'replacement'
        bridge.on_button(self.button('session:0', mid))
        self.assertIsNone(bridge.storage().get('codex', 'selected:codex'))
        self.assertIn('ended', bridge.TG.api.call_args.kwargs['text'])

    def test_pending_message_keeps_destination_if_selection_changes(self):
        self.panes.append(pane(2))
        bridge.storage().set('codex', 'selected:codex', tmux.identity(self.panes[0]))
        targets = bridge.capture_targets()
        bridge.storage().set('codex', 'selected:codex', tmux.identity(self.panes[1]))
        bridge._CONTEXT.targets = targets
        self.assertEqual(bridge.pick()[0]['id'], '%1')

    def test_pending_message_keeps_agent_if_picker_switches_to_other_agent(self):
        self.panes.append(pane(2, 'claude'))
        targets = bridge.capture_targets()
        bridge.storage().set('codex', 'active_agent', 'claude')
        bridge._CONTEXT.targets = targets
        self.assertEqual(bridge.pick()[0]['agent'], 'codex')

    def test_stop_cancels_pending_input_including_replies(self):
        self.route()
        targets = bridge.capture_targets()
        bridge.stop_task(self.panes[0], 2)
        bridge._CONTEXT.targets = targets
        for reply in (None, 7):
            p, r, error = bridge.pick(reply_to=reply)
            self.assertIsNone(error)
            with self.assertRaisesRegex(RuntimeError, 'cancelled by Stop'):
                bridge.send_text(p, r, 'should not run', 3)
            with self.assertRaisesRegex(RuntimeError, 'cancelled by Stop'):
                bridge.on_message(dict(message_id=4, text='/key Enter',
                                       reply_to_message={'message_id': reply} if reply else {}))
        tmux.checked.assert_not_called()

    def test_continue_is_held_while_busy_and_cannot_answer_approval(self):
        for screen in (BUSY, APPROVAL):
            tmux.screen.return_value = screen
            bridge.continue_task(self.panes[0], None, 2)
        tmux.checked.assert_not_called()

    def test_continue_cannot_start_twice_before_spinner_appears(self):
        self.panes[0]['state'] = 'working'
        with self.assertRaisesRegex(RuntimeError, 'still working'):
            bridge.continue_task(self.panes[0], None, 2)
        tmux.checked.assert_not_called()

    def test_identical_replacement_prompt_is_not_confirmed_with_enter(self):
        self.panes[0]['prompt'] = 'request1'
        r = self.route(kind='approval', opts=['1. Yes', '2. No'], anchor='npm test')
        tmux.screen.return_value = APPROVAL
        def new_request(*args, **kwargs):
            self.panes[0]['prompt'] = 'request2'
            return ''
        tmux.checked.side_effect = new_request
        ok, _ = bridge.press(copy.deepcopy(self.panes[0]), r, 1)
        self.assertTrue(ok)
        self.assertEqual(tmux.checked.call_count, 1)
        self.assertEqual(tmux.checked.call_args.args[-1], '1')

    def test_free_text_permission_is_bound_to_the_prompt_request(self):
        r = self.route(kind='typing', opts=['1. Yes', '2. No'], anchor='npm test')
        r['prompt'] = 'old-request'
        self.panes[0]['prompt'] = 'new-request'
        self.assertFalse(bridge.typing_allowed(r, APPROVAL, self.panes[0]))

    def test_stop_requests_escape_without_enter(self):
        self.panes[0]['state'] = 'working'
        tmux.screen.return_value = BUSY
        bridge.stop_task(self.panes[0], 2)
        self.assertEqual(tmux.checked.call_args_list[0].args,
                         ('send-keys', '-t', '%1', 'Escape'))
        self.assertFalse(any('Enter' in c.args for c in tmux.checked.call_args_list))

    def test_completion_card_routes_screen_replies(self):
        bridge.show_screen(self.panes[0], 1)
        self.assertIsNone(bridge.pick(reply_to=100)[2])

    def test_old_approval_button_does_not_press_a_key(self):
        self.route(kind='approval', opts=['1. Yes', '2. No'], anchor='npm test')
        path = self.root / 'routes.codex'
        import json
        r = telegram.route('codex', 7)
        r['t'] = int(time.time()) - 601
        path.write_text(json.dumps(r) + '\n')
        tmux.screen.return_value = APPROVAL
        bridge.on_button(self.button('opt:1'))
        tmux.checked.assert_not_called()

    def test_free_text_permission_expires_and_rejects_different_subject(self):
        r = self.route(kind='typing', opts=['1. Yes', '2. No'], anchor='npm test')
        self.assertTrue(bridge.typing_allowed(r, APPROVAL))
        self.assertFalse(bridge.typing_allowed(r, APPROVAL.replace('npm test', 'rm files')))
        r['t'] -= 601
        self.assertFalse(bridge.typing_allowed(r, APPROVAL))

    def test_wrong_sender_and_group_cannot_control_agent(self):
        self.assertFalse(bridge.authorized({'chat': {'id': 123, 'type': 'private'}}, {'id': 456}))
        self.assertFalse(bridge.authorized({'chat': {'id': 123, 'type': 'group'}}, {'id': 123}))
        self.route()
        q = self.button('ctl:continue')
        q['from']['id'] = 456
        bridge.on_button(q)
        tmux.checked.assert_not_called()

    def test_live_monitor_finishes_and_does_not_follow_replacement(self):
        self.panes[0]['state'] = 'working'
        bridge.control_panel(self.panes[0], 1)
        self.panes[0]['state'] = 'done'
        bridge.monitor_once()
        self.assertIn('Finished', bridge.TG.api.call_args.kwargs['text'])
        self.assertFalse(bridge.storage().get('codex', 'monitor:%1')['watching'])
        self.panes[0]['state'] = 'working'
        bridge.control_panel(self.panes[0], 1)
        self.panes[0]['instance'] = 'replacement'
        bridge.monitor_once()
        self.assertIsNone(bridge.storage().get('codex', 'monitor:%1'))
        self.assertIn('ended', bridge.TG.api.call_args.kwargs['text'])

    def test_live_status_does_not_take_over_a_question_free_text_route(self):
        self.panes[0]['state'] = 'working'
        bridge.control_panel(self.panes[0], 1)
        self.route(kind='typing', mid=7, opts=['1. Yes', '2. No'], anchor='npm test')
        self.panes[0]['state'] = 'waiting'
        tmux.screen.return_value = APPROVAL
        bridge.monitor_once()
        self.assertEqual(bridge.pick()[1]['kind'], 'typing')

    def test_refresh_edits_the_same_card_and_preserves_working_and_finished_time(self):
        for agent in ('claude', 'codex'):
            with self.subTest(agent=agent), patch.object(bridge.time, 'time', return_value=1000) as clock:
                bridge.BOT = agent
                self.panes = [dict(pane(agent=agent), state='working')]
                mid = bridge.control_panel(self.panes[0], 1)
                bridge.TG.send.reset_mock()
                clock.return_value = 1065
                bridge.on_button(self.button('ctl:refresh', mid))
                edit = bridge.TG.api.call_args
                self.assertEqual(edit.args, ('editMessageText',))
                self.assertEqual(edit.kwargs['message_id'], mid)
                self.assertIn('Elapsed: 1m 5s', edit.kwargs['text'])
                self.panes[0]['state'] = 'done'
                clock.return_value = 1090
                bridge.monitor_once()
                clock.return_value = 1500
                bridge.on_button(self.button('ctl:refresh', mid))
                self.assertIn('Finished', bridge.TG.api.call_args.kwargs['text'])
                self.assertIn('Elapsed: 1m 30s', bridge.TG.api.call_args.kwargs['text'])
                bridge.TG.send.assert_not_called()
                tmux.checked.assert_not_called()

    def test_completion_controls_open_a_card_without_editing_the_reply(self):
        self.route(kind='done')
        for action in ('ctl:open', 'ctl:refresh'):  # includes buttons sent by older hooks
            bridge.on_button(self.button(action))
        self.assertEqual(bridge.TG.send.call_count, 2)
        self.assertTrue(all(c.args == ('answerCallbackQuery',) for c in bridge.TG.api.call_args_list))
        self.assertEqual(telegram.route('codex', 7)['kind'], 'done')

    def test_final_status_retries_after_restart_and_respects_rate_limit(self):
        self.panes[0]['state'] = 'working'
        with patch.object(bridge.time, 'time', return_value=1000) as clock:
            mid = bridge.control_panel(self.panes[0], 1)
            self.panes[0]['state'] = 'done'
            clock.return_value = 1065
            bridge.TG.api.side_effect = [telegram.TelegramError('retry later', 429, 30), True]
            bridge.monitor_once()
            bridge._STORE = Store(self.root / 'bridge.sqlite3')
            clock.return_value = 1094
            bridge.monitor_once()
            self.assertEqual(bridge.TG.api.call_count, 1)
            clock.return_value = 1095
            bridge.monitor_once()
            self.assertEqual(bridge.TG.api.call_args.kwargs['message_id'], mid)
            self.assertIn('Elapsed: 1m 5s', bridge.TG.api.call_args.kwargs['text'])
            self.assertIn('Finished', bridge.TG.api.call_args.kwargs['text'])
            bridge.monitor_once()
            self.assertEqual(bridge.TG.api.call_count, 2)

    def test_session_end_edit_is_retried_and_a_deleted_card_is_retired(self):
        self.panes[0]['state'] = 'working'
        bridge.control_panel(self.panes[0], 1)
        self.panes.clear()
        bridge.TG.api.side_effect = [telegram.TelegramError('offline'),
                                     telegram.TelegramError('message to edit not found', 400)]
        bridge.monitor_once()
        self.assertIsNotNone(bridge.storage().get('codex', 'monitor:%1'))
        bridge.monitor_once()
        self.assertIn('ended', bridge.TG.api.call_args.kwargs['text'])
        self.assertIsNone(bridge.storage().get('codex', 'monitor:%1'))
        bridge.monitor_once()
        self.assertEqual(bridge.TG.api.call_count, 2)

    def test_already_updated_card_counts_as_delivered(self):
        self.panes[0]['state'] = 'working'
        mid = bridge.control_panel(self.panes[0], 1)
        self.panes[0]['state'] = 'done'
        bridge.TG.api.side_effect = telegram.TelegramError('Bad Request: message is not modified', 400)
        bridge.monitor_once()
        bridge.monitor_once()
        self.assertEqual(bridge.TG.api.call_count, 1)
        self.assertEqual(bridge.storage().get('codex', 'monitor:%1')['mid'], mid)

    def test_refresh_of_older_card_leaves_newer_monitor_active(self):
        self.panes[0]['state'] = 'working'
        first = bridge.control_panel(self.panes[0], 1)
        old = bridge.storage().get('codex', 'monitor:%1')
        second = bridge.control_panel(self.panes[0], 2)
        bridge.refresh_panel(first, old['route'], automatic=True)
        bridge.TG.api.assert_not_called()
        bridge.on_button(self.button('ctl:refresh', first))
        self.assertEqual(bridge.TG.api.call_args.kwargs['message_id'], first)
        self.assertEqual(bridge.storage().get('codex', 'monitor:%1')['mid'], second)

    def test_refreshed_prompt_buttons_stay_bound_to_the_original_question(self):
        self.panes[0].update(state='waiting', prompt='first')
        tmux.screen.return_value = APPROVAL
        mid = bridge.control_panel(self.panes[0], 1)
        def actions():
            rows = bridge.TG.api.call_args.kwargs['reply_markup']['inline_keyboard']
            return [b['callback_data'] for row in rows for b in row]
        bridge.on_button(self.button('ctl:refresh', mid))
        self.assertIn('opt:1', actions())
        self.panes[0]['prompt'] = 'second'
        bridge.on_button(self.button('ctl:refresh', mid))
        self.assertNotIn('opt:1', actions())
        self.assertIn('ctl:open', actions())
        self.assertEqual(telegram.route('codex', mid)['prompt'], 'first')
        bridge.on_button(self.button('opt:1', mid))
        tmux.checked.assert_not_called()
        bridge.on_button(self.button('ctl:open', mid))
        new = bridge.storage().get('codex', 'monitor:%1')['mid']
        self.assertNotEqual(new, mid)
        self.assertEqual(telegram.route('codex', new)['prompt'], 'second')

    def test_replaced_prompt_is_checked_after_acquiring_the_terminal_lock(self):
        self.panes[0]['prompt'] = 'first'
        old = self.panes[0].copy()
        r = self.route(kind='approval', opts=['1. Yes', '2. No'], anchor='npm test')
        self.panes[0]['prompt'] = 'second'
        tmux.screen.return_value = APPROVAL
        self.assertFalse(bridge.press(old, r, 1)[0])
        tmux.checked.assert_not_called()

    def test_session_picker_includes_state_and_selected_destination(self):
        self.panes[0]['state'] = 'working'
        self.panes.append(dict(pane(2, 'claude'), state='waiting'))
        bridge.pick('codex')
        bridge.on_message(dict(message_id=1, text='/list'))
        rows = bridge.TG.send.call_args.kwargs['buttons']
        self.assertIn('✓ Codex · Working', rows[0][0]['text'])
        self.assertIn('Claude · Waiting for your answer', rows[1][0]['text'])

    def test_screenshot_caption_is_sent_as_text_with_local_image_path(self):
        msg = dict(message_id=1, photo=[dict(file_id='photo', width=100, height=100)],
                   caption='Explain this error')
        with patch.object(bridge.media, 'download', return_value=(Path('/private/image.jpg'), 'image')):
            bridge.on_message(msg)
        paste = next(c for c in tmux.checked.call_args_list if c.args[0] == 'load-buffer')
        self.assertIn('Explain this error', paste.kwargs['input'])
        self.assertIn('/private/image.jpg', paste.kwargs['input'])

    def test_attachment_cannot_reach_replacement_session_during_download(self):
        def changed(*args):
            self.panes[0]['instance'] = 'replacement'
            return Path('/private/image.jpg'), 'image'
        with patch.object(bridge.media, 'download', side_effect=changed):
            with self.assertRaisesRegex(RuntimeError, 'ended'):
                bridge.on_message(dict(message_id=1, photo=[dict(file_id='photo')]))
        tmux.checked.assert_not_called()

    def test_failed_paste_never_reports_message_sent(self):
        tmux.checked.side_effect = RuntimeError('terminal disconnected')
        with self.assertRaisesRegex(RuntimeError, 'disconnected'):
            bridge.on_message(dict(message_id=1, text='check build'))
        bridge.TG.send.assert_not_called()

    def test_input_worker_survives_a_receipt_failure_and_handles_the_next_request(self):
        inbox = Mock()
        inbox.get.side_effect = [(1, {'text': 'first'}, {}), (2, {'text': 'second'}, {}), KeyboardInterrupt]
        with patch.object(bridge, 'handle_message', side_effect=[RuntimeError('database busy'), None]) as handle:
            with self.assertRaises(KeyboardInterrupt):
                bridge.message_worker(inbox)
        self.assertEqual(handle.call_count, 2)
        self.assertEqual(inbox.task_done.call_count, 2)


class TerminalTests(unittest.TestCase):
    def test_real_foreground_restart_changes_identity_without_restarting_shell(self):
        import fcntl
        import subprocess
        import termios
        master, slave = os.openpty()
        def prepare():
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        process = None
        try:
            process = subprocess.Popen(['/bin/sh', '-i'], stdin=slave, stdout=slave, stderr=slave,
                                       preexec_fn=prepare)
            os.close(slave)
            slave = None
            def wait_for(predicate):
                end = time.monotonic() + 2
                while time.monotonic() < end:
                    value = tmux.process_instance(process.pid)
                    if predicate(value):
                        return value
                    time.sleep(.01)
                self.fail('The isolated foreground process did not reach the expected state')
            wait_for(lambda v: f':{process.pid}:' in v)
            os.write(master, b'sleep 20\n')
            first = wait_for(lambda v: bool(v) and f':{process.pid}:' not in v)
            os.write(master, b'\x03')
            wait_for(lambda v: f':{process.pid}:' in v)
            os.write(master, b'sleep 20\n')
            second = wait_for(lambda v: bool(v) and f':{process.pid}:' not in v)
            self.assertNotEqual(first, second)
        finally:
            os.close(master)
            if slave is not None:
                os.close(slave)
            if process:
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()

    def test_overlapping_pastes_cannot_share_or_steal_buffers(self):
        buffers, pasted, errors = {}, {}, []
        barrier = threading.Barrier(2)

        def checked(*args, input=None):
            if args[0] == 'load-buffer':
                buffers[args[2]] = input
                barrier.wait(timeout=3)
            elif args[0] == 'paste-buffer':
                pasted[args[-1]] = buffers.pop(args[4])
            return ''

        def send(target, text):
            try:
                tmux.paste(target, text, lambda: None)
            except Exception as e:
                errors.append(e)

        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, XDG_STATE_HOME=tmp), \
                patch.object(tmux, 'checked', side_effect=checked), patch.object(tmux, 'tmux'), \
                patch('time.sleep'):
            threads = [threading.Thread(target=send, args=(p, text))
                       for p, text in [('%1', 'Claude request'), ('%2', 'Codex request')]]
            for t in threads:
                t.start()
            for t in threads:
                t.join(timeout=5)
            self.assertFalse(any(t.is_alive() for t in threads))
        self.assertEqual(errors, [])
        self.assertEqual(pasted, {'%1': 'Claude request', '%2': 'Codex request'})
        self.assertEqual(buffers, {})

    def test_entire_command_is_checked_when_approval_prefixes_match(self):
        shared = 'python script.py --long-common-prefix=' + 'a' * 50
        self.assertFalse(tmux.shows(shared + 'safe', shared + 'unsafe'))


if __name__ == '__main__':
    unittest.main()
