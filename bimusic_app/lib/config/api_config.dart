// coverage:ignore-file
class ApiConfig {
  const ApiConfig._();

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
