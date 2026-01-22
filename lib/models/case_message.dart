import 'package:flutter/foundation.dart';

// 案件消息列表項模型
class CaseMessageListItem {
  final int id;
  final String caseNumber;
  final String caseState;
  final String driverName;
  final String driverNickName;
  final String dispatcherName;
  final String dispatcherNickName;
  final LatestMessage? latestMessage;
  final int unreadCount;
  final DateTime createTime;
  final String? onAddress; // 案件上車地址

  CaseMessageListItem({
    required this.id,
    required this.caseNumber,
    required this.caseState,
    required this.driverName,
    required this.driverNickName,
    required this.dispatcherName,
    required this.dispatcherNickName,
    this.latestMessage,
    required this.unreadCount,
    required this.createTime,
    this.onAddress,
  });

  factory CaseMessageListItem.fromJson(Map<String, dynamic> json) {
    return CaseMessageListItem(
      id: json['id'],
      caseNumber: json['case_number'] ?? '',
      caseState: json['case_state'] ?? '',
      driverName: json['driver_name'] ?? '',
      driverNickName: json['driver_nick_name'] ?? '',
      dispatcherName: json['dispatcher_name'] ?? '',
      dispatcherNickName: json['dispatcher_nick_name'] ?? '',
      latestMessage: json['latest_message'] != null
          ? LatestMessage.fromJson(json['latest_message'])
          : null,
      unreadCount: json['unread_count'] ?? 0,
      createTime: json['create_time'] != null
          ? DateTime.parse(json['create_time'])
          : DateTime.now(),
      onAddress: json['on_address'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'case_number': caseNumber,
      'case_state': caseState,
      'driver_name': driverName,
      'driver_nick_name': driverNickName,
      'dispatcher_name': dispatcherName,
      'dispatcher_nick_name': dispatcherNickName,
      'latest_message': latestMessage?.toJson(),
      'unread_count': unreadCount,
      'create_time': createTime.toIso8601String(),
      'on_address': onAddress,
    };
  }
}

// 最新消息模型
class LatestMessage {
  final int id;
  final String messageType;
  final String content;
  final String? imageUrl;
  final int senderId;
  final String senderName;
  final DateTime createdAt;

  LatestMessage({
    required this.id,
    required this.messageType,
    required this.content,
    this.imageUrl,
    required this.senderId,
    required this.senderName,
    required this.createdAt,
  });

  factory LatestMessage.fromJson(Map<String, dynamic> json) {
    return LatestMessage(
      id: json['id'],
      messageType: json['message_type'] ?? 'text',
      content: json['content'] ?? '',
      imageUrl: json['image_url'],
      senderId: json['sender_id'],
      senderName: json['sender_name'] ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'message_type': messageType,
      'content': content,
      'image_url': imageUrl,
      'sender_id': senderId,
      'sender_name': senderName,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

// 案件消息詳細模型
class CaseMessage {
  final int id;
  final int caseId;
  final int sender;
  final String senderName;
  final String senderNickName;
  final String messageType;
  final String content;
  final String? imageUrl;
  final String? imageKey;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;

  CaseMessage({
    required this.id,
    required this.caseId,
    required this.sender,
    required this.senderName,
    required this.senderNickName,
    required this.messageType,
    required this.content,
    this.imageUrl,
    this.imageKey,
    required this.isRead,
    this.readAt,
    required this.createdAt,
  });

  bool isFromCurrentUser(int currentUserId) {
    return sender == currentUserId;
  }

  factory CaseMessage.fromJson(Map<String, dynamic> json) {
    return CaseMessage(
      id: json['id'],
      caseId: json['case'],
      sender: json['sender'],
      senderName: json['sender_name'] ?? '',
      senderNickName: json['sender_nick_name'] ?? '',
      messageType: json['message_type'] ?? 'text',
      content: json['content'] ?? '',
      imageUrl: json['image_url'],
      imageKey: json['image_key'],
      isRead: json['is_read'] ?? false,
      readAt: json['read_at'] != null ? DateTime.parse(json['read_at']) : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'case': caseId,
      'sender': sender,
      'sender_name': senderName,
      'sender_nick_name': senderNickName,
      'message_type': messageType,
      'content': content,
      'image_url': imageUrl,
      'image_key': imageKey,
      'is_read': isRead,
      'read_at': readAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

