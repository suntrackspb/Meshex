import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'bot.dart';
import 'protocol.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2 || !const {'configure', 'run'}.contains(args.first)) {
    stderr.writeln(
      'Usage: dart telegram_bridge.dart <configure|run> <config.json>',
    );
    exitCode = 64;
    return;
  }

  final configFile = File(args.last);
  try {
    if (args.first == 'configure') {
      await _configure(configFile);
    } else {
      await _run(await _readConfig(configFile));
    }
  } on BridgeError catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } on TelegramError catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } on FileSystemException {
    stderr.writeln('Could not read or write the module configuration file.');
    exitCode = 1;
  } on FormatException {
    stderr.writeln(
      'Invalid configuration or module protocol. Run configure to create a configuration.',
    );
    exitCode = 1;
  }
}

typedef _Config = ({String token, TelegramOwner owner});

Future<_Config> _readConfig(File file) async {
  final config = bridgeObject(jsonDecode(await file.readAsString()));
  if (config['version'] != 1) {
    throw const FormatException('Invalid module configuration version');
  }
  final token = config['token'];
  final user = config['user'];
  final chat = config['chat'];
  if (token is! String ||
      !validTelegramBotToken(token) ||
      user is! int ||
      chat is! int ||
      user <= 0 ||
      chat <= 0) {
    throw const FormatException('Invalid configuration');
  }
  return (token: token, owner: (user: user, chat: chat));
}

Future<void> _configure(File file) async {
  if (!stdin.hasTerminal) {
    throw const BridgeError(
      -32000,
      'Run configure in an interactive terminal.',
    );
  }
  if (await file.exists()) {
    await _readConfig(file);
    stderr.write('Replace the existing Telegram configuration? [y/N] ');
    if (stdin.readLineSync()?.trim().toLowerCase() != 'y') return;
  }
  stderr.write('Token from BotFather: ');
  final echo = stdin.echoMode;
  String? token;
  try {
    stdin.echoMode = false;
    token = stdin.readLineSync()?.trim();
  } finally {
    stdin.echoMode = echo;
    stderr.writeln();
  }
  if (token == null || !validTelegramBotToken(token)) {
    throw const BridgeError(-32000, 'Enter a valid token from BotFather.');
  }

  final candidate = Completer<TelegramOwner>();
  late final TelegramBot bot;
  bot = TelegramBot(
    token,
    owner: null,
    onPairingChanged: () {
      final choice = bot.candidate;
      if (choice != null && !candidate.isCompleted) candidate.complete(choice);
    },
  );
  try {
    await bot.open(
      (_, _) async => throw const BridgeError(-32000, 'Pairing in progress'),
      () {
        if (!candidate.isCompleted) {
          candidate.completeError(
            const BridgeError(
              -32000,
              'Bot disconnected. Stop any other instance and retry.',
            ),
          );
        }
      },
    );
    stderr.writeln(
      'Open the one-time link and press Start in the private bot chat.',
    );
    stderr.writeln(bot.pairingUrl);
    final selected = await candidate.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => throw const BridgeError(
        -32000,
        'Pairing expired. Run configure again.',
      ),
    );
    stderr.write('Enter the account ID shown in Telegram to confirm: ');
    if (stdin.readLineSync()?.trim() != selected.user.toString()) {
      throw const BridgeError(
        -32000,
        'Account ID did not match. Pairing cancelled.',
      );
    }
    await _saveConfig(file, (token: token, owner: selected));
    stderr.writeln('Telegram account ${selected.user} linked.');
  } finally {
    bot.close();
  }
}

Future<void> _saveConfig(File file, _Config config) async {
  final target = file.absolute;
  await target.parent.create(recursive: true);
  final random = Random.secure();
  final temp = File('${target.path}.${random.nextInt(1 << 32)}.tmp');
  await temp.create(exclusive: true);
  try {
    if (!Platform.isWindows) {
      final permissions = await Process.run('/bin/chmod', ['600', temp.path]);
      if (permissions.exitCode != 0) {
        throw const BridgeError(
          -32000,
          'Could not protect the configuration file.',
        );
      }
    }
    await temp.writeAsString(
      jsonEncode({
        'version': 1,
        'token': config.token,
        'user': config.owner.user,
        'chat': config.owner.chat,
      }),
      flush: true,
    );
    await temp.rename(target.path);
  } finally {
    if (await temp.exists()) await temp.delete();
  }
}

Future<void> _run(_Config config) async {
  final rpc = StdioRpc(stdin, writeStdioFrame);
  final bot = TelegramBot(
    config.token,
    owner: config.owner,
    onPairingChanged: () {},
  );
  try {
    await rpc.listen(
      onInitialize: () => bot.open(rpc.request, () {
        stderr.writeln(
          'Telegram disconnected. Check the token and stop any other instance of this bot.',
        );
        exit(1);
      }),
      onEvent: bot.publish,
      onEventError: (error) {
        stderr.writeln(
          error is TelegramError ? error : 'Could not forward the mesh event.',
        );
      },
    );
  } finally {
    bot.close();
  }
}
