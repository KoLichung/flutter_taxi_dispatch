class User {
  final int? id;
  final String phone;
  final String? name;
  final String? nickName;
  final bool isLoggedIn;

  User({
    this.id,
    required this.phone,
    this.name,
    this.nickName,
    this.isLoggedIn = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      phone: json['phone'] ?? '',
      name: json['name'],
      nickName: json['nick_name'] ?? json['nickName'],
      isLoggedIn: json['isLoggedIn'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone': phone,
      'name': name,
      'nick_name': nickName,
      'isLoggedIn': isLoggedIn,
    };
  }

  User copyWith({
    int? id,
    String? phone,
    String? name,
    String? nickName,
    bool? isLoggedIn,
  }) {
    return User(
      id: id ?? this.id,
      phone: phone ?? this.phone,
      name: name ?? this.name,
      nickName: nickName ?? this.nickName,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
    );
  }
} 