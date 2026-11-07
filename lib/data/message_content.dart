import '../core/proto/mesh.dart';
import 'database.dart';

bool isTextMessage(Message message) =>
    message.portnum == PortNum.TEXT_MESSAGE_APP.value;

String messageTextPreview(Message message, String unsupportedLabel) =>
    isTextMessage(message) ? message.body : unsupportedLabel;
