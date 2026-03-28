import 'package:flutter_test/flutter_test.dart';

import 'package:bimusic_app/models/auth_tokens.dart';
import 'package:bimusic_app/models/user.dart';

void main() {
  const testUser = User(
    userId: 'user-123',
    username: 'testuser',
    isAdmin: false,
  );

  const adminUser = User(
    userId: 'admin-1',
    username: 'admin',
    isAdmin: true,
  );

  group('AuthTokens', () {
    test('constructs with required fields', () {
      const tokens = AuthTokens(
        accessToken: 'access-abc',
        refreshToken: 'refresh-xyz',
        user: testUser,
      );

      expect(tokens.accessToken, 'access-abc');
      expect(tokens.refreshToken, 'refresh-xyz');
      expect(tokens.user.userId, 'user-123');
      expect(tokens.user.username, 'testuser');
      expect(tokens.user.isAdmin, isFalse);
    });

    group('fromJson', () {
      test('parses all fields correctly', () {
        final json = {
          'accessToken': 'access-tok',
          'refreshToken': 'refresh-tok',
          'user': {
            'userId': 'u1',
            'username': 'bob',
            'isAdmin': false,
          },
        };

        final tokens = AuthTokens.fromJson(json);

        expect(tokens.accessToken, 'access-tok');
        expect(tokens.refreshToken, 'refresh-tok');
        expect(tokens.user.userId, 'u1');
        expect(tokens.user.username, 'bob');
        expect(tokens.user.isAdmin, isFalse);
      });

      test('parses admin user', () {
        final json = {
          'accessToken': 'tok',
          'refreshToken': 'rtok',
          'user': {
            'userId': 'admin-1',
            'username': 'admin',
            'isAdmin': true,
          },
        };

        final tokens = AuthTokens.fromJson(json);
        expect(tokens.user.isAdmin, isTrue);
      });
    });

    group('toJson (via freezed)', () {
      test('includes accessToken and refreshToken in the map', () {
        const tokens = AuthTokens(
          accessToken: 'access-abc',
          refreshToken: 'refresh-xyz',
          user: adminUser,
        );

        final map = tokens.toJson();

        expect(map['accessToken'], 'access-abc');
        expect(map['refreshToken'], 'refresh-xyz');
        expect(map.containsKey('user'), isTrue);
      });
    });
  });

  group('User', () {
    test('constructs and exposes fields', () {
      const user = User(
        userId: 'u-abc',
        username: 'alice',
        isAdmin: true,
      );

      expect(user.userId, 'u-abc');
      expect(user.username, 'alice');
      expect(user.isAdmin, isTrue);
    });

    test('fromJson parses all fields', () {
      final user = User.fromJson({
        'userId': 'u-123',
        'username': 'charlie',
        'isAdmin': false,
      });

      expect(user.userId, 'u-123');
      expect(user.username, 'charlie');
      expect(user.isAdmin, isFalse);
    });

    test('toJson produces correct map', () {
      const user = User(userId: 'u1', username: 'dan', isAdmin: true);
      final map = user.toJson();

      expect(map['userId'], 'u1');
      expect(map['username'], 'dan');
      expect(map['isAdmin'], isTrue);
    });
  });
}
