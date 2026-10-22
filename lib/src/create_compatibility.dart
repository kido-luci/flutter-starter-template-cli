/// Validates cross-flag rules for `fst create` before the command acquires or
/// modifies a template.
///
/// Returns an actionable error message for the first unsupported combination,
/// or `null` when the resolved configuration is supported.
String? validateCreateCompatibility({
  required bool minimal,
  required bool useFirebase,
  required bool useBackend,
  required bool useAuth,
  required String authProvider,
  bool firebaseExplicitlyEnabled = false,
  bool backendExplicitlyEnabled = false,
  bool authExplicitlyEnabled = false,
  bool authProviderWasParsed = false,
  bool apiUrlWasParsed = false,
  bool useDocumentEngine = true,
  bool useDocumentCenter = true,
  bool documentEngineExplicitlyEnabled = false,
  bool documentCenterExplicitlyEnabled = false,
}) {
  if (minimal && firebaseExplicitlyEnabled) {
    return '--minimal disables Firebase and cannot be combined with '
        '--firebase. Remove one of the flags.';
  }
  if (minimal && backendExplicitlyEnabled) {
    return '--minimal disables the backend and cannot be combined with '
        '--backend. Remove one of the flags.';
  }
  if (minimal && authExplicitlyEnabled) {
    return '--minimal disables authentication and cannot be combined with '
        '--auth. Remove one of the flags.';
  }
  if (minimal && documentEngineExplicitlyEnabled) {
    return '--minimal disables Document Engine and cannot be combined with '
        '--document-engine. Remove one of the flags.';
  }
  if (minimal && documentCenterExplicitlyEnabled) {
    return '--minimal disables Document Center and cannot be combined with '
        '--document-center. Remove one of the flags.';
  }

  if (!useDocumentEngine &&
      (useDocumentCenter || documentCenterExplicitlyEnabled)) {
    return '--document-center requires Document Engine. Remove '
        '--no-document-engine or pass --no-document-center.';
  }

  if (!useAuth && authProviderWasParsed) {
    return '--auth-provider has no effect when authentication is disabled. '
        'Remove --auth-provider or pass --auth.';
  }

  if (authProvider == 'firebase') {
    if (!useFirebase) {
      return '--auth-provider firebase requires Firebase. Remove '
          '--no-firebase (or --minimal), or select --auth-provider jwt.';
    }
    if (!useBackend) {
      return '--auth-provider firebase requires the backend pillar. Remove '
          '--no-backend (or --minimal), or select --auth-provider jwt.';
    }
    if (!useAuth) {
      return '--auth-provider firebase requires authentication. Remove '
          '--no-auth, or select --auth-provider jwt.';
    }
  }

  if (!useBackend && !useAuth && apiUrlWasParsed) {
    return '--api-url has no consumer when both backend and authentication '
        'are disabled. Remove --api-url, or retain --backend/--auth.';
  }

  return null;
}
