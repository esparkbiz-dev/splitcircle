/// Thrown for any business-rule violation (validation, authorization, state).
class AppException implements Exception {
  final String message;
  const AppException(this.message);
  @override
  String toString() => message;
}
