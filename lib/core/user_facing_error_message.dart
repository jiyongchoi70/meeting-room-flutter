// Dart `Exception('…')` 의 `toString()` 에 붙는 `Exception:` 접두어 제거(스낵바 표시용).
String userFacingErrorMessage(Object error) {
  return error
      .toString()
      .replaceFirst(RegExp(r'^Exception\s*:\s*', caseSensitive: false), '')
      .trim();
}
