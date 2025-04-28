import 'package:flutter/foundation.dart';

class Message {
  final int id;
  final String content;
  final int? sender;
  final int? recipient;
  final Map<String, dynamic>? senderDetails;
  final Map<String, dynamic>? recipientDetails;
  final bool isFromServer;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.content,
    this.sender,
    this.recipient,
    this.senderDetails,
    this.recipientDetails,
    this.isFromServer = false,
    required this.createdAt,
  });

  bool get isFromUser => !isFromServer;

  factory Message.fromJson(Map<String, dynamic> json) {
    // Handle different formats of the is_from_server field
    bool isFromServer = false;
    if (json['is_from_server'] != null) {
      if (json['is_from_server'] is bool) {
        isFromServer = json['is_from_server'];
      } else if (json['is_from_server'] is int) {
        isFromServer = json['is_from_server'] == 1;
      } else if (json['is_from_server'] is String) {
        isFromServer = json['is_from_server'].toLowerCase() == 'true' || json['is_from_server'] == '1';
      }
    }
    
    // debugPrint('Parsing message: id=${json['id']}, isFromServer=$isFromServer (original: ${json['is_from_server']}), content="${json['content']?.toString().substring(0, json['content'].toString().length > 20 ? 20 : json['content'].toString().length)}..."');
    
    return Message(
      id: json['id'] is String ? int.parse(json['id']) : json['id'],
      content: json['content'] ?? '',
      sender: json['sender'],
      recipient: json['recipient'],
      senderDetails: json['sender_details'],
      recipientDetails: json['recipient_details'],
      isFromServer: isFromServer,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : (json['timestamp'] != null 
              ? DateTime.parse(json['timestamp']) 
              : DateTime.now()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'sender': sender,
      'recipient': recipient,
      'sender_details': senderDetails,
      'recipient_details': recipientDetails,
      'is_from_server': isFromServer,
      'created_at': createdAt.toIso8601String(),
    };
  }
} 