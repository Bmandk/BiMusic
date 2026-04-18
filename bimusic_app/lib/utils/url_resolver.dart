/// Prepends [base] to [pathOrUrl] when [pathOrUrl] is a relative path.
///
/// Uses [Uri.tryParse] to detect an absolute URL (has scheme). If [base] is
/// empty and [pathOrUrl] is relative, returns [pathOrUrl] unchanged.
String resolveBackendUrl(String base, String pathOrUrl) {
  final uri = Uri.tryParse(pathOrUrl);
  if (uri != null && uri.hasScheme) return pathOrUrl;
  if (base.isEmpty) return pathOrUrl;
  final trimmedBase =
      base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  final trimmedPath =
      pathOrUrl.startsWith('/') ? pathOrUrl : '/$pathOrUrl';
  return '$trimmedBase$trimmedPath';
}
