import 'package:swagger_generator/src/extensions/string_extension.dart';

String getClassNameFromFileName(String file) {
  final String name = file.split('.').first;
  final Iterable<String> result =
      name.split('_').map((String e) => e.capitalize);
  return result.join();
}

String getFileNameWithoutExtension(String file) {
  return file.split('.').first;
}
