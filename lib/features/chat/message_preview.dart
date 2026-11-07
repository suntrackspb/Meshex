import 'package:flutter/widgets.dart';

import '../../data/database.dart';
import '../../data/message_content.dart';
import '../../l10n/l10n.dart';

String messagePreview(BuildContext context, Message message) =>
    messageTextPreview(message, context.l10n.unsupportedMessage);
