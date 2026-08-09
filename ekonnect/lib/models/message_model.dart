import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime timestamp;
  final bool isSystem;

  const MessageModel({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.timestamp,
    this.isSystem = false,
  });

  factory MessageModel.fromMap(String id, Map<String, dynamic> map) {
    return MessageModel(
      id: id,
      senderId: map['senderId'] ?? '',
      senderName: map['senderName'] ?? '',
      text: map['text'] ?? '',
      timestamp: map['timestamp'] != null
          ? (map['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      isSystem: map['isSystem'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'senderId': senderId,
        'senderName': senderName,
        'text': text,
        'timestamp': Timestamp.fromDate(timestamp),
        'isSystem': isSystem,
      };
}
