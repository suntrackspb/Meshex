#!/usr/bin/env python3
"""Standalone Telegram adapter for Meshex Bridge API v1."""

import argparse
import base64
from collections import OrderedDict
from concurrent.futures import Future, TimeoutError
import getpass
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
from queue import Empty, Full, Queue
import re
import secrets
import sys
import tempfile
from threading import Condition, Event, Lock, Thread
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


FRAME_LIMIT = 256 * 1024


class BridgeError(Exception):
    pass


class TelegramError(BridgeError):
    def __init__(self, code, retry_after=None):
        self.code = code
        self.retry_after = retry_after
        super().__init__({
            0: "Нет связи с Telegram Bot API.",
            401: "Telegram отклонил токен бота.",
            409: "Обновления этого бота уже получает другой процесс.",
        }.get(code, f"Ошибка Telegram Bot API ({code})."))


class Telegram:
    def __init__(self, token):
        self.token = token
        self.send_lock = Lock()

    def call(self, method, params=None, timeout=10, upload=None):
        params = params or {}
        if upload is None:
            body = json.dumps(params).encode("utf-8")
            content_type = "application/json"
        else:
            field, media = upload
            boundary = secrets.token_hex(24)
            parts = []
            for name, value in params.items():
                value = str(value) if isinstance(value, (str, int)) else json.dumps(value)
                parts.append(
                    f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"'
                    f"\r\n\r\n{value}\r\n".encode("utf-8")
                )
            parts.extend((
                f'--{boundary}\r\nContent-Disposition: form-data; name="{field}"; '
                'filename="sticker.webp"\r\nContent-Type: image/webp\r\n\r\n'.encode("ascii"),
                media, f"\r\n--{boundary}--\r\n".encode("ascii"),
            ))
            body = b"".join(parts)
            content_type = f"multipart/form-data; boundary={boundary}"
        request = Request(
            f"https://api.telegram.org/bot{self.token}/{method}", body,
            {"Content-Type": content_type},
        )
        try:
            with urlopen(request, timeout=timeout) as response:
                data = json.load(response)
        except HTTPError as error:
            try:
                with error:
                    data = json.load(error)
            except (ValueError, OSError):
                raise TelegramError(error.code) from None
        except (URLError, OSError, ValueError):
            raise TelegramError(0) from None
        if not data.get("ok"):
            delay = data.get("parameters", {}).get("retry_after")
            delay = delay if type(delay) is int and 0 <= delay <= 30 else None
            raise TelegramError(data.get("error_code", 0), delay)
        return data["result"]

    def updates(self, offset, timeout=20):
        return self.call(
            "getUpdates",
            {"offset": offset, "timeout": timeout, "allowed_updates": ["message"]},
            timeout=timeout + 8,
        )

    def send(self, chat, text, *, reply_to=None):
        with self.send_lock:
            for attempt in range(3):
                try:
                    params = {"chat_id": chat, "text": text[:4096],
                              "link_preview_options": {"is_disabled": True}}
                    if reply_to is not None:
                        params["reply_parameters"] = {"message_id": reply_to,
                                                      "allow_sending_without_reply": True}
                    return self.call("sendMessage", params)["message_id"]
                except TelegramError as error:
                    if attempt == 2 or error.retry_after is None:
                        raise
                    time.sleep(error.retry_after)


    def send_sticker(self, chat, media, *, animated, reply_to):
        params = {"chat_id": chat, "reply_parameters": {
            "message_id": reply_to, "allow_sending_without_reply": True,
        }}
        with self.send_lock:
            if not animated:
                try:
                    return self.call("sendSticker", params, upload=("sticker", media))["message_id"]
                except TelegramError as error:
                    if error.code != 400:
                        raise
            return self.call("sendDocument", params, upload=("document", media))["message_id"]


def private_sender(message):
    chat = message.get("chat") or {}
    sender = message.get("from") or {}
    if chat.get("type") != "private":
        return None
    ids = sender.get("id"), chat.get("id")
    if all(type(value) is int and value > 0 for value in ids):
        return ids
    return None


def configure(path):
    if not sys.stdin.isatty():
        raise BridgeError("Запусти configure в интерактивном терминале.")
    if path.exists():
        try:
            previous = load_config(path)
        except (BridgeError, ValueError):
            raise BridgeError("По этому пути уже есть другой файл.") from None
        if input("Заменить привязку Telegram в этом файле? [y/N] ").strip().lower() != "y":
            return
    else:
        previous = {}
    token = getpass.getpass("Токен от BotFather: ").strip()
    if not re.fullmatch(r"\d+:[A-Za-z0-9_-]{20,}", token):
        raise BridgeError("Проверь токен от BotFather.")
    telegram = Telegram(token)
    username = telegram.call("getMe").get("username", "")
    if not re.fullmatch(r"[A-Za-z0-9_]{1,64}", username):
        raise BridgeError("Telegram вернул некорректное имя бота.")
    if telegram.call("getWebhookInfo").get("url"):
        raise BridgeError("У этого бота настроен webhook. Используй отдельного бота.")
    code = secrets.token_urlsafe(24)
    print(f"Открой ссылку и нажми Start в личном чате:\nhttps://t.me/{username}?start={code}")
    started = int(time.time())
    deadline = time.monotonic() + 300
    offset = 0
    while time.monotonic() < deadline:
        for update in telegram.updates(offset, timeout=10):
            offset = update["update_id"] + 1
            message = update.get("message") or {}
            owner = private_sender(message)
            if (not owner or message.get("text") != f"/start {code}"
                    or message.get("date", 0) < started):
                continue
            telegram.send(owner[1], f"Твой ID Telegram: {owner[0]}. Введи его в терминале.")
            if input("ID аккаунта из Telegram: ").strip() != str(owner[0]):
                raise BridgeError("ID не совпал. Привязка отменена.")
            save_config(path, {
                "version": 1, "token": token, "user": owner[0], "chat": owner[1],
                "http_token": previous.get("http_token") or secrets.token_urlsafe(32),
            })
            print("Аккаунт Telegram привязан.")
            return
    raise BridgeError("Срок действия ссылки истёк. Запусти configure ещё раз.")


def load_config(path):
    config = json.loads(path.read_text(encoding="utf-8"))
    if (not isinstance(config, dict) or config.get("version") != 1
            or not isinstance(config.get("token"), str)
            or not re.fullmatch(r"\d+:[A-Za-z0-9_-]{20,}", config["token"])
            or any(type(config.get(key)) is not int or config[key] <= 0 for key in ("user", "chat"))
            or not isinstance(config.get("http_token"), str)
            or not re.fullmatch(r"[A-Za-z0-9_-]{32,}", config["http_token"])):
        raise BridgeError("Некорректная конфигурация Python-модуля. Запусти configure.")
    return config


def save_config(path, config):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.NamedTemporaryFile(
        mode="w", dir=path.parent, encoding="utf-8", delete=False,
    ) as temp:
        name = temp.name
        try:
            json.dump(config, temp)
            temp.close()
            os.replace(name, path)
        finally:
            if os.path.exists(name):
                os.unlink(name)


class Meshex:
    """A single outstanding RPC request, retained until the host replies."""

    def __init__(self, write=None):
        self.write = write
        self.ready = Event()
        self.closed = Event()
        self.events = Queue(maxsize=128)
        self.condition = Condition()
        self.request_lock = Lock()
        self.pending = None

    def receive(self, frame):
        if not isinstance(frame, dict) or frame.get("jsonrpc") != "2.0":
            raise BridgeError("Некорректный пакет JSON-RPC.")
        method = frame.get("method")
        rpc_id = frame.get("id")
        if method == "bridge.initialize" and isinstance(rpc_id, str):
            reply = {"jsonrpc": "2.0", "id": rpc_id}
            params = frame.get("params")
            if isinstance(params, dict) and params.get("apiVersion") == 1:
                reply["result"] = {"apiVersion": 1}
            else:
                reply["error"] = {"code": -32000, "message": "Bridge API v1 required"}
            return reply
        if not self.ready.is_set():
            raise BridgeError("Сначала Meshex должен выполнить bridge.initialize.")
        if method in ("mesh.messageReceived", "mesh.deliveryChanged",
                      "mesh.reactionReceived", "mesh.stickerReceived") and rpc_id is None:
            params = frame.get("params")
            if not isinstance(params, dict):
                raise BridgeError("Некорректные параметры уведомления.")
            try:
                self.events.put_nowait((method, params))
            except Full:
                print("Очередь уведомлений заполнена.", file=sys.stderr)
        elif method is None and isinstance(rpc_id, str):
            with self.condition:
                if self.pending and self.pending[0]["id"] == rpc_id:
                    future = self.pending[1]
                    self.pending = None
                    if isinstance(frame.get("error"), dict):
                        future.set_exception(BridgeError(frame["error"].get("message", "Ошибка Meshex.")))
                    elif isinstance(frame.get("result"), dict):
                        future.set_result(frame["result"])
                    else:
                        future.set_exception(BridgeError("Некорректный ответ Meshex."))
        return None

    def request(self, method, params):
        with self.request_lock:
            return self._request(method, params)

    def _request(self, method, params):
        frame = {
            "jsonrpc": "2.0", "id": secrets.token_hex(12),
            "method": method, "params": params,
        }
        future = Future()
        with self.condition:
            if self.closed.is_set() or not self.ready.is_set():
                raise BridgeError("Meshex не подключён.")
            if self.pending is not None:
                raise BridgeError("Meshex уже обрабатывает команду.")
            self.pending = (frame, future)
            self.condition.notify_all()
        try:
            if self.write:
                self.write(frame)
            return future.result(timeout=20)
        except TimeoutError:
            raise BridgeError("Meshex не ответил. Проверь чат перед повторной отправкой.") from None
        finally:
            with self.condition:
                if self.pending and self.pending[1] is future:
                    self.pending = None

    def next_request(self):
        with self.condition:
            self.condition.wait_for(lambda: self.pending or self.closed.is_set(), timeout=20)
            return self.pending[0] if self.pending else None

    def close(self):
        self.closed.set()
        self.ready.set()
        with self.condition:
            if self.pending:
                self.pending[1].set_exception(BridgeError("Соединение с Meshex закрыто."))
                self.pending = None
            self.condition.notify_all()


class Bot:
    def __init__(self, telegram, owner, meshex):
        self.telegram = telegram
        self.owner = owner
        self.meshex = meshex
        self.replies = OrderedDict()
        self.targets = {}
        self.target_numbers = {}
        self.lock = Lock()

    def handle_message(self, update):
        message = update.get("message") or {}
        text = message.get("text")
        if private_sender(message) != self.owner or not isinstance(text, str):
            return
        text = text.strip()
        if not text:
            return
        parts = text.split(maxsplit=1)
        command = parts[0]
        args = parts[1] if len(parts) == 2 else ""
        try:
            reply = self.command(command, args, text, message, update["update_id"])
        except BridgeError as error:
            reply = str(error)
        self.telegram.send(self.owner[1], reply)

    def command(self, command, args, text, message, update_id):
        if command in ("/start", "/help"):
            return ("Ответь на сообщение бота, чтобы написать в тот же mesh-чат.\n"
                    "/targets [поиск] — список адресатов\n"
                    "/send <номер> <текст> — новое сообщение\n"
                    "/mention <текст> — ответ с упоминанием автора в канале\n"
                    "/react <эмодзи> — реакция на сообщение")
        if command == "/targets":
            result = self.meshex.request("mesh.listTargets", {"query": args} if args else {})
            lines = []
            for target in result["targets"][:25]:
                address = result["nodeId"], target["id"]
                number = self.target_numbers.get(address)
                if number is None:
                    number = str(len(self.targets) + 1)
                    self.targets[number] = address
                    self.target_numbers[address] = number
                label = " ".join(target["name"].splitlines())
                if target["kind"] == "channel":
                    label = "#" + label
                else:
                    label += f" ({target['id'].removeprefix('dm:')})"
                lines.append(f"{number}. {label}")
            return "\n".join(lines) or "Доступных адресатов нет."

        params = {"commandId": f"telegram:{update_id}"}
        if command == "/send":
            parts = args.split(maxsplit=1)
            target = self.targets.get(parts[0]) if len(parts) == 2 else None
            if target is None:
                return "Сначала вызови /targets, затем /send <номер> <текст>."
            params.update(nodeId=target[0], targetId=target[1], text=parts[1])
        else:
            parent = message.get("reply_to_message") or {}
            with self.lock:
                reply = self.replies.get(parent.get("message_id"))
            if reply is None or (command.startswith("/") and command not in ("/mention", "/react")):
                return "Ответь на недавнее сообщение бота или вызови /help."
            node, reference, channel = reply
            if command == "/mention" and not channel:
                return "Команда /mention работает в ответе на сообщение канала."
            params.update(nodeId=node, replyRef=reference, text=text)
            if command == "/mention":
                params.update(text=args, mentionAuthor=True)
            elif command == "/react":
                params.update(text=args, reaction=True)
        if not params["text"].strip():
            return "Введи текст сообщения."
        result = self.meshex.request("mesh.sendMessage", params)
        return ("В очереди на отправку в mesh." if result.get("status") == "queued"
                else "Результат отправки неизвестен. Проверь чат перед повтором.")

    def forward_events(self):
        while not self.meshex.closed.is_set():
            try:
                method, event = self.meshex.events.get(timeout=0.5)
            except Empty:
                continue
            try:
                self.forward(method, event)
            except TelegramError as error:
                print(error, file=sys.stderr)
            except (KeyError, TypeError):
                print("Некорректное уведомление от Meshex.", file=sys.stderr)

    def forward(self, method, event):
        if method == "mesh.deliveryChanged":
            status = event["status"]
            description = {
                "acked": "Сеть mesh подтвердила пакет.",
                "timeout": "Подтверждение доставки не пришло.",
                "unknown": "Статус доставки неизвестен.",
            }.get(status, f"Ошибка отправки в mesh ({event.get('error', status)}).")
            if status == "acked":
                proof = event.get("ackProof")
                if proof == "ACK_PROOF_VALID":
                    description = "Получатель подтвердил доставку."
                elif proof == "ACK_PROOF_INVALID":
                    description = "Не удалось проверить подтверждение доставки."
            self.telegram.send(self.owner[1], description)
            return
        target, author = event["target"], event["author"]
        is_channel = target["kind"] == "channel"
        label = f"#{target['name']}" if is_channel else "Личка"
        sender = f"{label} · {author['name']} ({author['id']})"
        if method == "mesh.reactionReceived":
            original = event.get("originalRef")
            with self.lock:
                parent = next((mid for mid, value in reversed(self.replies.items())
                               if value[1] == original), None)
            if parent is None:
                packet = event.get("radio", {}).get("replyId")
                self.telegram.send(self.owner[1], f"{sender}\nРеакция {event['emoji']} на пакет {packet}")
            else:
                self.telegram.send(self.owner[1], f"{sender}\nРеакция {event['emoji']}", reply_to=parent)
            return
        if method == "mesh.stickerReceived":
            sticker = event["sticker"]
            identity = f"{sticker['pack_sha256'][:12]}/{sticker['sticker_id']}"
            try:
                media, animated = self.sticker_media(event["replyRef"])
            except (BridgeError, ValueError, KeyError, TypeError):
                media = None
            with self.lock:
                suffix = f"Стикер {identity}" if media else f"Стикер {identity} · медиа недоступно"
                header = self.telegram.send(self.owner[1], f"{sender}\n{suffix}")
                self.remember(header, event, is_channel)
                if media:
                    message_id = self.telegram.send_sticker(
                        self.owner[1], media, animated=animated, reply_to=header,
                    )
                    self.remember(message_id, event, is_channel)
        else:
            with self.lock:
                message_id = self.telegram.send(self.owner[1], f"{sender}\n{event['text']}")
                self.remember(message_id, event, is_channel)

    def remember(self, message_id, event, is_channel):
        self.replies[message_id] = event["nodeId"], event["replyRef"], is_channel
        if len(self.replies) > 512:
            self.replies.popitem(last=False)

    def sticker_media(self, reference):
        media = bytearray()
        size = None
        animated = False
        while size is None or len(media) < size:
            result = self.meshex.request(
                "mesh.getStickerMedia", {"replyRef": reference, "offset": len(media)},
            )
            if size is None:
                size = result["size"]
                animated = result["animated"]
            chunk = base64.b64decode(result["dataBase64"], validate=True)
            if (type(size) is not int or not 1 <= size <= 5 * 1024 * 1024 or
                    result["size"] != size or not chunk or len(media) + len(chunk) > size):
                raise ValueError("Invalid sticker media")
            media.extend(chunk)
        return bytes(media), animated

    def poll(self):
        self.meshex.ready.wait()
        offset = 0
        failures = 0
        started = int(time.time())
        while not self.meshex.closed.is_set():
            try:
                updates = self.telegram.updates(offset)
            except TelegramError as error:
                if error.code in (401, 409):
                    raise
                failures += 1
                if failures >= 4:
                    raise
                self.meshex.closed.wait(error.retry_after or failures)
                continue
            failures = 0
            for update in updates:
                if self.meshex.closed.is_set():
                    return
                offset = update["update_id"] + 1
                if (update.get("message") or {}).get("date", 0) < started:
                    continue
                try:
                    self.handle_message(update)
                except TelegramError as error:
                    print(error, file=sys.stderr)


def stdio_reader(meshex):
    buffer = bytearray()
    try:
        while not meshex.closed.is_set():
            chunk = os.read(sys.stdin.fileno(), 16384)
            if not chunk:
                return
            buffer.extend(chunk)
            while (newline := buffer.find(b"\n")) != -1:
                if newline > FRAME_LIMIT:
                    raise BridgeError("Пакет Meshex слишком большой.")
                frame = json.loads(bytes(buffer[:newline]).decode("utf-8"))
                del buffer[:newline + 1]
                response = meshex.receive(frame)
                if response is not None:
                    meshex.write(response)
                    if "result" not in response:
                        return
                    meshex.ready.set()
            if len(buffer) > FRAME_LIMIT:
                raise BridgeError("Пакет Meshex слишком большой.")
    except (OSError, ValueError, BridgeError):
        print("Соединение по stdin/stdout завершилось с ошибкой.", file=sys.stderr)
    finally:
        meshex.close()


def run_stdio(config):
    lock = Lock()

    def write(frame):
        data = (json.dumps(frame, ensure_ascii=False) + "\n").encode("utf-8")
        with lock:
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()

    meshex = Meshex(write)
    bot = Bot(Telegram(config["token"]), (config["user"], config["chat"]), meshex)
    Thread(target=stdio_reader, args=(meshex,), daemon=True).start()
    Thread(target=bot.forward_events, daemon=True).start()
    try:
        bot.poll()
    finally:
        meshex.close()


def run_http(config, port):
    meshex = Meshex()
    token = f"Bearer {config['http_token']}".encode("ascii")

    class Handler(BaseHTTPRequestHandler):
        def authorized(self):
            if self.path != "/rpc":
                self.send_error(404)
                return False
            if not hmac.compare_digest(self.headers.get("Authorization", "").encode(), token):
                self.send_error(401)
                return False
            return True

        def reply(self, data):
            if data is None:
                self.send_response(204)
                self.end_headers()
                return
            body = json.dumps(data, ensure_ascii=False).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.authorized():
                if not meshex.ready.is_set():
                    self.send_error(409)
                    return
                self.reply(meshex.next_request())

        def do_POST(self):
            if not self.authorized():
                return
            try:
                size = int(self.headers.get("Content-Length", "0"))
                if not 0 < size <= FRAME_LIMIT:
                    self.send_error(413)
                    return
                self.connection.settimeout(10)
                frame = json.loads(self.rfile.read(size).decode("utf-8"))
                response = meshex.receive(frame)
                self.reply(response)
                if response and "result" in response:
                    meshex.ready.set()
            except (ValueError, BridgeError):
                self.send_error(400)

        def log_message(self, *args):
            pass

    bot = Bot(Telegram(config["token"]), (config["user"], config["chat"]), meshex)
    failure = []
    with ThreadingHTTPServer(("127.0.0.1", port), Handler) as server:
        def poll():
            try:
                bot.poll()
            except TelegramError as error:
                failure.append(error)
                server.shutdown()

        print(f"Адрес Meshex: http://127.0.0.1:{server.server_port}", file=sys.stderr)
        print(f"Токен HTTP-подключения: {config['http_token']}", file=sys.stderr)
        Thread(target=poll, daemon=True).start()
        Thread(target=bot.forward_events, daemon=True).start()
        try:
            server.serve_forever()
        finally:
            meshex.close()
    if failure:
        raise failure[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="mode", required=True)
    for mode in ("configure", "run", "serve"):
        command = commands.add_parser(mode)
        command.add_argument("config", type=Path)
        if mode == "serve":
            command.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    try:
        if args.mode == "configure":
            configure(args.config.expanduser())
        else:
            config = load_config(args.config.expanduser())
            if args.mode == "serve":
                if not 1 <= args.port <= 65535:
                    parser.error("--port должен быть от 1 до 65535")
                run_http(config, args.port)
            else:
                run_stdio(config)
    except KeyboardInterrupt:
        return 0
    except BridgeError as error:
        print(error, file=sys.stderr)
        return 1
    except (OSError, ValueError):
        print("Проверь путь к конфигурации и доступность локального порта.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
