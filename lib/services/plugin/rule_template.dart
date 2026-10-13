/// Matches `@name` placeholders that are not part of a longer word, so an
/// e-mail-like `user@host` is left alone.
final RegExp ruleTemplateVariable = RegExp(
  r'(?<![A-Za-z0-9_])@([A-Za-z_][A-Za-z0-9_]*)',
);

/// Replaces `@name` placeholders in [template] with [variables].
///
/// [encode] is applied to each substituted value. A placeholder without a
/// variable throws the exception built by [onMissing].
String renderRuleTemplate(
  String template,
  Map<String, Object?> variables, {
  String Function(String value)? encode,
  required Exception Function(String name) onMissing,
}) {
  return template.replaceAllMapped(ruleTemplateVariable, (match) {
    final name = match.group(1)!;
    if (!variables.containsKey(name)) throw onMissing(name);
    final value = variables[name]?.toString() ?? '';
    return encode == null ? value : encode(value);
  });
}
