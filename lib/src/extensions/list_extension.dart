extension RegExpExtension on List<String> {
  bool containsAllowRegExp(String value) {
    return any((element) {
      final RegExp regularExpression = RegExp(element);
      return regularExpression.hasMatch(value);
    });
  }
}