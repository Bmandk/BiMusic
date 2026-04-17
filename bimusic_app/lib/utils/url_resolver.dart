/// Prepends [base] to [pathOrUrl] when [pathOrUrl] is a relative path.
/// If [pathOrUrl] already begins with "http", it is returned unchanged.
String resolveBackendUrl(String base, String pathOrUrl) {
  if (pathOrUrl.startsWith('http')) return pathOrUrl;
  return '$base$pathOrUrl';
}
