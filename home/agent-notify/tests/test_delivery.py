import io
import http.client
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.local/lib/agent-notify'))
from agentnotify import media, telegram
from agentnotify.store import Store


class BotApiTests(unittest.TestCase):
    def setUp(self):
        self.bot = telegram.Bot('codex', ('test-token', 123))

    def response(self, data):
        response = io.BytesIO(data)
        response.status = 200
        return response

    def test_incomplete_or_unexpected_poll_response_retries_with_the_same_offset(self):
        for data in (None, b'{"ok":true}', b'[]', b'{"ok":'):
            with self.subTest(data=data):
                broken = self.response(data or b'')
                if data is None:
                    broken.read = Mock(side_effect=http.client.IncompleteRead(b'partial'))
                good = self.response(b'{"ok":true,"result":[{"update_id":12}]}')
                with patch.object(telegram.urllib.request, 'urlopen', side_effect=[broken, good]) as post, \
                        patch.object(telegram.time, 'sleep') as wait:
                    result = self.bot.api('getUpdates', offset=12, retries=1)
                self.assertEqual(result, [{'update_id': 12}])
                self.assertEqual(post.call_args_list[0], post.call_args_list[1])
                wait.assert_called_once_with(2)
                self.assertTrue(broken.closed)

    def test_error_body_honors_retry_after_and_redacts_tokens(self):
        slow = self.response(b'{"ok":false,"error_code":429,"parameters":{"retry_after":15}}')
        denied = telegram.urllib.error.HTTPError('https://example.invalid', 403, 'Forbidden', {},
                                                 io.BytesIO(b'{"description":"denied test-token"}'))
        with patch.object(telegram.urllib.request, 'urlopen', side_effect=[slow, denied]) as post, \
                patch.object(telegram.time, 'sleep') as wait, self.assertRaises(telegram.TelegramError) as err:
            self.bot.api('editMessageText', retries=3)
        self.assertEqual(post.call_count, 2)
        wait.assert_called_once_with(15)
        self.assertEqual(err.exception.code, 403)
        self.assertNotIn('test-token', str(err.exception))


class PersistenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'bridge.sqlite3'
        self.store = Store(self.path)

    def test_command_is_not_replayed_after_crash_and_recovery_is_reported_once(self):
        self.assertTrue(self.store.claim('codex', 10))
        restarted = Store(self.path)
        self.assertFalse(restarted.claim('codex', 10))
        self.assertEqual(restarted.get('codex', 'offset'), 11)
        self.assertEqual(restarted.recover('codex'), 1)
        self.assertEqual(restarted.recover('codex'), 0)

    def test_update_ids_and_preferences_are_separate_for_both_bots(self):
        self.assertTrue(self.store.claim('claude', 10))
        self.assertTrue(self.store.claim('codex', 10))
        self.store.set('claude', 'selected', '%1')
        self.assertIsNone(self.store.get('codex', 'selected'))

    def test_cursor_never_regresses(self):
        self.store.claim('codex', 100)
        self.store.claim('codex', 10)
        self.assertEqual(self.store.get('codex', 'offset'), 101)

    def test_finished_commands_do_not_report_uncertainty(self):
        self.store.claim('codex', 10)
        self.store.finish('codex', 10)
        self.assertEqual(self.store.recover('codex'), 0)
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)


class OutboxTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.sender = Mock()
        self.sender.send.return_value = 100
        for p in [patch.object(telegram, 'STATE', self.root),
                  patch.object(telegram, 'Bot', return_value=self.sender),
                  patch.object(telegram, 'muted', return_value=False)]:
            p.start()
            self.addCleanup(p.stop)
        self.store = Store(self.root / 'bridge.sqlite3')

    def make_due(self):
        with self.store.db() as db:
            db.execute('UPDATE outbox SET due=0')

    def test_failed_alert_survives_restart_and_resumes_after_last_delivered_part(self):
        telegram.queue_alert('codex', ['first', 'second'], route=dict(kind='done', pane='%1'))
        self.sender.send.side_effect = [100, telegram.TelegramError('offline')]
        telegram.flush_outbox('codex')
        self.make_due()
        job = Store(self.root / 'bridge.sqlite3').pending('codex')[0]
        self.assertEqual(job['payload']['next'], 1)
        self.sender.send.reset_mock()
        self.sender.send.side_effect = [101]
        telegram.flush_outbox('codex')
        self.sender.send.assert_called_once()
        self.assertEqual(self.sender.send.call_args.args[0], 'second')
        self.assertEqual(self.store.pending('codex'), [])
        self.assertEqual(telegram.route('codex', 101)['pane'], '%1')

    def test_mute_keeps_queued_alert_until_unmuted(self):
        telegram.queue_alert('claude', ['finished'])
        with patch.object(telegram, 'muted', return_value=True):
            telegram.flush_outbox('claude')
        self.sender.send.assert_not_called()
        telegram.flush_outbox('claude')
        self.sender.send.assert_called_once()

    def test_expired_prompt_is_not_delivered_after_reconnect(self):
        from agentnotify import tmux
        telegram.queue_alert('codex', ['approve?'], route=dict(kind='approval', pane='%1'))
        with patch.object(tmux, 'panes', return_value=[]):
            telegram.flush_outbox('codex')
        self.sender.send.assert_not_called()
        self.assertEqual(self.store.pending('codex'), [])

    def test_permanent_bot_error_is_not_retried_forever(self):
        telegram.queue_alert('codex', ['finished'])
        self.sender.send.side_effect = telegram.TelegramError('blocked', 403)
        telegram.flush_outbox('codex')
        self.assertEqual(self.store.pending('codex'), [])

    def test_current_approval_is_delivered_but_identical_replacement_is_discarded(self):
        from agentnotify import tmux
        p = dict(id='%1', agent='codex', cmd='codex', instance='boot:1:10',
                 session='s1', generation='', prompt='request1', state='waiting')
        screen = 'npm test\n❯ 1. Yes\n  2. No'
        with patch.object(tmux, 'panes', return_value=[p]), \
                patch.object(tmux, 'server', return_value='server'), \
                patch.object(tmux, 'screen', return_value=screen):
            route = dict(tmux.identity(p), kind='approval', opts=['1. Yes', '2. No'], anchor='npm test')
            telegram.queue_alert('codex', ['Run npm test?'], route=route)
            telegram.flush_outbox('codex')
            self.sender.send.assert_called_once()
            self.sender.send.reset_mock()
            telegram.queue_alert('codex', ['Run npm test?'], route=route)
            p['prompt'] = 'request2'
            telegram.flush_outbox('codex')
            self.sender.send.assert_not_called()
            self.assertEqual(self.store.pending('codex'), [])


class AttachmentTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bot = Mock(token='secret-token')
        self.bot.api.return_value = dict(file_path='photos/file.jpg', file_size=4)
        p = patch.object(telegram, 'STATE', self.root)
        p.start()
        self.addCleanup(p.stop)

    def test_selects_largest_photo(self):
        result = media.attachment(dict(photo=[dict(file_id='small', width=10, height=10),
                                             dict(file_id='large', width=100, height=100)]))
        self.assertEqual(result[0]['file_id'], 'large')

    def test_file_is_private_uniquely_named_and_cannot_escape_attachment_folder(self):
        item = (dict(file_id='f'), '../../bad name;$(command).pdf', 'file')
        with patch.object(media.urllib.request, 'urlopen', return_value=io.BytesIO(b'data')):
            path, kind = media.download(self.bot, item)
        self.assertEqual(path.parent, self.root / 'attachments')
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(path.read_bytes(), b'data')
        self.assertEqual(kind, 'file')
        self.assertNotIn('$', path.name)

    def test_large_metadata_is_rejected_before_download(self):
        item = (dict(file_id='f', file_size=media.MAX_BYTES + 1), 'file.bin', 'file')
        with self.assertRaisesRegex(ValueError, 'too large'):
            media.download(self.bot, item)
        self.bot.api.assert_not_called()

    def test_stream_size_limit_cleans_up_partial_file(self):
        with patch.object(media, 'MAX_BYTES', 4), \
                patch.object(media.urllib.request, 'urlopen', return_value=io.BytesIO(b'12345')):
            with self.assertRaisesRegex(ValueError, 'too large'):
                media.download(self.bot, (dict(file_id='f'), 'file.bin', 'file'))
        self.assertEqual(list((self.root / 'attachments').iterdir()), [])

    def test_network_errors_do_not_disclose_bot_token(self):
        with patch.object(media.urllib.request, 'urlopen', side_effect=OSError('secret-token in URL')):
            with self.assertRaises(ValueError) as caught:
                media.download(self.bot, (dict(file_id='f'), 'file.bin', 'file'))
        self.assertNotIn('secret-token', str(caught.exception))

    def test_partial_file_is_removed_when_a_download_ends_early(self):
        for size_source in ('getFile', 'message', 'Content-Length'):
            with self.subTest(size_source=size_source):
                item = dict(file_id='f')
                self.bot.api.return_value = dict(file_path='photos/file.jpg')
                response = io.BytesIO(b'ab')
                response.headers = {}
                if size_source == 'getFile':
                    self.bot.api.return_value['file_size'] = 4
                elif size_source == 'message':
                    item['file_size'] = 4
                else:
                    response.headers['Content-Length'] = '4'
                with patch.object(media.urllib.request, 'urlopen', return_value=response), \
                        self.assertRaisesRegex(ValueError, 'incomplete'):
                    media.download(self.bot, (item, 'photo.jpg', 'image'))
                self.assertEqual(list((self.root / 'attachments').iterdir()), [])

    def test_invalid_telegram_path_is_rejected(self):
        self.bot.api.return_value = dict(file_path='../../outside')
        with self.assertRaisesRegex(ValueError, 'usable attachment'):
            media.download(self.bot, (dict(file_id='f'), 'file.bin', 'file'))


if __name__ == '__main__':
    unittest.main()
