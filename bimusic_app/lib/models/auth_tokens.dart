import 'package:freezed_annotation/freezed_annotation.dart';

import 'user.dart';

part 'auth_tokens.freezed.dart';
part 'auth_tokens.g.dart';

@freezed
class AuthTokens with _$AuthTokens {
  const factory AuthTokens({
    required String accessToken,
    required String refreshToken,
    required User user,
  }) = _AuthTokens;

  factory AuthTokens.fromJson(Map<String, dynamic> json) =>
      _$AuthTokensFromJson(json);
}
