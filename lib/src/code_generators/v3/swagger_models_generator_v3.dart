import 'dart:convert';
import 'package:recase/recase.dart';
import 'package:swagger_generator/src/code_generators/swagger_models_generator.dart';
import 'package:swagger_generator/src/extensions/string_extension.dart';
import 'package:swagger_generator/src/models/generator_options.dart';
import 'package:meta/meta.dart';
import 'package:swagger_generator/src/exception_words.dart';

class SwaggerModelsGeneratorV3 implements SwaggerModelsGenerator {
  static const defaultEnumValueName = "swaggerGeneratedUnknown";

  String generate(String dartCode, String fileName, GeneratorOptions options) {
    final dynamic map = jsonDecode(dartCode);

    final Map<String, dynamic> definitions =
        map['components']['schemas'] as Map<String, dynamic>;

    if (definitions == null) {
      return '';
    }

    return definitions.keys.map((className) {
      return generateModelClassContent(
        className.pascalCase,
        definitions[className],
        options.defaultValuesMap,
        options.useDefaultNullForLists,
      );
    }).join("\n");
  }

  String generateModelClassContent(
    String className,
    Map<String, dynamic> map,
    List<DefaultValueMap> defaultValues,
    bool useDefaultNullForLists,
  ) {
    if (map['enum'] != null) {
      return _generateEnumContentIfPossible(map, className);
    }

    final properties = map['properties'] as Map<String, dynamic>;
    final String generatedConstructorProperties =
        generateConstructorPropertiesContent(properties);

    final generatedProperties = _generatePropertiesContent(
        properties, className, defaultValues, useDefaultNullForLists);

    final String enums = generateEnumsContent(properties, className);

    final String generatedClass = """
@JsonSerializable(explicitToJson: true)
class $className{
\t$className($generatedConstructorProperties);\n
\tfactory $className.fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);\n
$generatedProperties
\tstatic const fromJsonFactory = _\$${className}FromJson;
\tstatic const toJsonFactory = _\$${className}ToJson;
\tMap<String, dynamic> toJson() => _\$${className}ToJson(this);
}

$enums
""";

    return generatedClass;
  }

  String generateConstructorPropertiesContent(Map<String, dynamic> entityMap) {
    if (entityMap == null) {
      return '';
    }

    final String generatedConstructorParameters = entityMap.keys.map((key) {
      final fieldName = generateFieldName(key);
      return "\t\tthis.$fieldName,";
    }).join("\n");

    return '{\n\t${generatedConstructorParameters.toString()}\t}';
  }

  String generateEnumsContent(Map<String, dynamic> map, String className) {
    if (map == null) {
      return '';
    }

    var gemeratedEnumsContent = map.keys
        .map((key) {
          final Map<String, dynamic> enumValuesMap =
              map[key] as Map<String, dynamic>;

          if (enumValuesMap.containsKey('type')) {
            return _generateEnumContentIfPossible(
                enumValuesMap, generateEnumName(className, key));
          }

          return '';
        })
        .where((generatedEnum) => generatedEnum.isNotEmpty)
        .join("\n");

    return gemeratedEnumsContent;
  }

  @visibleForTesting
  String generateEnumName(String className, String enumName) {
    return "${className.capitalize}${enumName.capitalize}";
  }

  String _generateEnumContentIfPossible(
      Map<String, dynamic> map, String enumName) {
    if (map['enum'] != null) {
      return """
enum ${enumName.capitalize} {
\t@JsonValue('$defaultEnumValueName')\n  $defaultEnumValueName,
${generateEnumValuesContent(map['enum'] as List<dynamic>)}
}
""";
    } else if (map['items'] != null) {
      return _generateEnumContentIfPossible(
          map['items'] as Map<String, dynamic>, enumName);
    } else {
      return '';
    }
  }

  String generateEnumValuesContent(List<dynamic> values) {
    return values
        .map((dynamic e) => "\t@JsonValue('$e')\n  ${getEnumFieldName(e)}")
        .join(',\n');
  }

  String _generatePropertiesContent(
    Map<String, dynamic> propertiesMap,
    String className,
    List<DefaultValueMap> defaultValues,
    bool useDefaultNullForLists,
  ) {
    if (propertiesMap == null) {
      return '';
    }

    final List<String> results = <String>[];

    for (int i = 0; i < propertiesMap.keys.length; i++) {
      String propertyName = propertiesMap.keys.elementAt(i);
      final Map<String, dynamic> propertyEntryMap =
          propertiesMap[propertyName] as Map<String, dynamic>;
      String propertyKey = propertyName;

      exceptionWords.forEach((String exceptionWord) {
        if (propertyName == exceptionWord) {
          propertyName = '\$' + propertyName;
        }
      });

      if (propertyEntryMap.containsKey('type')) {
        results.add(_generatePropertyContentByType(
            propertyEntryMap,
            propertyName,
            propertyKey,
            className,
            defaultValues,
            useDefaultNullForLists));
      } else if (propertyEntryMap['\$ref'] != null) {
        results.add(_generatePropertyContentByRef(
            propertyEntryMap, propertyName, propertyKey, className));
      } else if (propertyEntryMap['schema'] != null) {
        results.add(_generatePropertyContentBySchema(
            propertyEntryMap, propertyName, propertyKey, className));
      } else {
        results.add(
            _generatePropertyContentByDefault(propertyEntryMap, propertyName));
      }
    }

    return results.join("\n");
  }

  String _generateListPropertyContent(
      String propertyName,
      String propertyKey,
      String className,
      Map<String, dynamic> propertyEntryMap,
      bool useDefaultNullForLists) {
    final dynamic items = propertyEntryMap['items'];

    String typeName;
    if (items != null) {
      typeName = items['originalRef'];
    }

    if (typeName == null) {
      typeName = getParameterTypeName(
          className, propertyName, items as Map<String, dynamic>);
    }

    final String jsonKeyContent =
        "@JsonKey(name: '$propertyKey'${useDefaultNullForLists ? ')\n' : ', defaultValue: <$typeName>[])\n'}";

    return """  $jsonKeyContent  final List<$typeName> ${generateFieldName(propertyName)};""";
  }

  String _generateEnumPropertyContent(String key, String className) {
    return """
  @JsonKey(unknownEnumValue: ${className.capitalize + key.capitalize}.swaggerGeneratedUnknown)
  final ${className.capitalize + key.capitalize} ${generateFieldName(key)};""";
  }

  String _generateGeneralPropertyContent(
      String propertyName,
      String propertyKey,
      String className,
      List<DefaultValueMap> defaultValues,
      Map<String, dynamic> val) {
    String jsonKeyContent = "@JsonKey(name: '$propertyKey'";
    final String typeName = getParameterTypeName(className, propertyName, val);

    if (defaultValues
        .any((DefaultValueMap element) => element.typeName == typeName)) {
      final DefaultValueMap defaultValue = defaultValues.firstWhere(
          (DefaultValueMap element) => element.typeName == typeName);
      jsonKeyContent +=
          ", defaultValue: ${generateDefaultValueFromMap(defaultValue)})\n";
    } else {
      jsonKeyContent += ')\n';
    }
    return """  $jsonKeyContent  final $typeName ${generateFieldName(propertyName)};""";
  }

  String _generatePropertyContentByType(
      Map<String, dynamic> propertyEntryMap,
      String propertyName,
      String propertyKey,
      String className,
      List<DefaultValueMap> defaultValues,
      bool useDefaultNullForLists) {
    switch (propertyEntryMap['type']) {
      case 'array':
        return _generateListPropertyContent(propertyName, propertyKey,
            className, propertyEntryMap, useDefaultNullForLists);
        break;
      case 'enum':
        return _generateEnumPropertyContent(propertyName, className);
        break;
      default:
        return _generateGeneralPropertyContent(propertyName, propertyKey,
            className, defaultValues, propertyEntryMap);
    }
  }

  String _generatePropertyContentByRef(Map<String, dynamic> propertyEntryMap,
      String propertyName, String propertyKey, String className) {
    String jsonKeyContent = "@JsonKey(name: '$propertyKey'";

    final String parameterName =
        propertyEntryMap['\$ref'].toString().split('/').last;

    String _typeName = getParameterTypeName(
        className, propertyName, propertyEntryMap, parameterName);

    return "\t$jsonKeyContent)\n  final $_typeName ${generateFieldName(propertyName)};";
  }

  String _generatePropertyContentBySchema(Map<String, dynamic> propertyEntryMap,
      String propertyName, String propertyKey, String className) {
    String jsonKeyContent = "@JsonKey(name: '$propertyKey'";

    final Map propertySchema = propertyEntryMap['schema'];

    final String parameterName =
        propertySchema['\$ref'].toString().split('/').last;

    String _typeName = getParameterTypeName(
        className, propertyName, propertyEntryMap, parameterName);
    return "\t$jsonKeyContent)\n\tfinal $_typeName ${generateFieldName(propertyName)};";
  }

  String _generatePropertyContentByDefault(
      Map<String, dynamic> propertyEntryMap, String propertyName) {
    String jsonKeyContent = "@JsonKey(name: '$propertyName'";
    return "\t$jsonKeyContent)\n  final ${propertyEntryMap['originalRef']} ${generateFieldName(propertyName)};";
  }

  @visibleForTesting
  String generateDefaultValueFromMap(DefaultValueMap map) {
    switch (map.typeName) {
      case 'int':
      case 'double':
      case 'bool':
        return map.defaultValue;
      default:
        return "'${map.defaultValue}'";
    }
  }

  @visibleForTesting
  String generateFieldName(String jsonKey) {
    final List<String> forbiddenCharacters = <String>['#'];
    jsonKey = jsonKey.camelCase;

    forbiddenCharacters.forEach((String element) {
      if (jsonKey.startsWith(element)) {
        jsonKey = '\$forbiddenFieldName';
      }
    });

    if (jsonKey.startsWith(RegExp('[0-9]')) || jsonKey == 'null') {
      jsonKey = '\$' + jsonKey;
    }
    return jsonKey;
  }

  @visibleForTesting
  String getParameterTypeName(
      String className, String parameterName, Map<String, dynamic> parameter,
      [String nameParameter]) {
    if (nameParameter != null) {
      return nameParameter.pascalCase;
    }

    if (parameter == null) {
      return 'Object';
    }

    if (parameter['\$ref'] != null) {
      return parameter['\$ref'].toString().split('/').last.pascalCase;
    }

    switch (parameter['type'] as String) {
      case 'integer':
        return 'int';
      case 'boolean':
        return 'bool';
      case 'string':
        if (parameter['format'] == 'date-time' ||
            parameter['format'] == 'date') {
          return 'DateTime';
        } else if (parameter['enum'] != null) {
          return generateEnumName(className, parameterName);
        }
        return 'String';
      case 'number':
        return 'double';
      case 'object':
        return 'Object';
      case 'array':
        final Map<String, dynamic> items =
            parameter['items'] as Map<String, dynamic>;
        return getParameterTypeName(className, parameterName, items);
      default:
        if (parameter['oneOf'] != null) {
          return 'Object';
        }
        return 'undefinedType';
    }
  }

  @visibleForTesting
  String getEnumFieldName(dynamic dynamicName) {
    String name = dynamicName.toString();

    exceptionWords.forEach((String forbiddenWord) {
      if (name == forbiddenWord) {
        name = '\$' + name;
      }
    });

    String result = name
        .replaceAll(' ', '_')
        .replaceAll('-', '_')
        .replaceAll('.', '_')
        .replaceAll(',', '_')
        .split('_')
        .map((String e) => e.toLowerCase().capitalize)
        .join();

    if (result.startsWith(RegExp('[0-9]'))) {
      result = '\$' + result;
    }

    return result.lower;
  }
}
