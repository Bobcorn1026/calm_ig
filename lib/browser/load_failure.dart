import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Network-level failures that leave the page blank. Everything else is
/// ignored on purpose: CANCELLED / UNKNOWN also fire when calm_ig itself
/// cancels a navigation (blocked Reels link, `instagram://` app link), and
/// sub-frame or image failures don't break the page.
final _networkFailures = {
  WebResourceErrorType.NOT_CONNECTED_TO_INTERNET,
  WebResourceErrorType.NETWORK_CONNECTION_LOST,
  WebResourceErrorType.TIMEOUT,
  WebResourceErrorType.HOST_LOOKUP,
  WebResourceErrorType.CANNOT_CONNECT_TO_HOST,
  WebResourceErrorType.CANNOT_LOAD_FROM_NETWORK,
  WebResourceErrorType.SERVER_UNREACHABLE,
  WebResourceErrorType.SECURE_CONNECTION_FAILED,
  WebResourceErrorType.DATA_NOT_ALLOWED,
  WebResourceErrorType.INTERNATIONAL_ROAMING_OFF,
  WebResourceErrorType.RESOURCE_UNAVAILABLE,
  WebResourceErrorType.BAD_SERVER_RESPONSE,
  WebResourceErrorType.CONNECTION_ABORTED,
  WebResourceErrorType.RESET,
  // Wi-Fi that wants you to log in first (hotel, school) or a wrong clock.
  WebResourceErrorType.SERVER_CERTIFICATE_UNTRUSTED,
  WebResourceErrorType.SERVER_CERTIFICATE_HAS_BAD_DATE,
  WebResourceErrorType.SERVER_CERTIFICATE_NOT_YET_VALID,
  WebResourceErrorType.SERVER_CERTIFICATE_HAS_UNKNOWN_ROOT,
};

final _certificateFailures = {
  WebResourceErrorType.SERVER_CERTIFICATE_UNTRUSTED,
  WebResourceErrorType.SERVER_CERTIFICATE_HAS_BAD_DATE,
  WebResourceErrorType.SERVER_CERTIFICATE_NOT_YET_VALID,
  WebResourceErrorType.SERVER_CERTIFICATE_HAS_UNKNOWN_ROOT,
};

/// Where 重新載入 should go: the page that failed, or home if nothing has
/// loaded yet (WKWebView can't reload an empty view). Null means a normal
/// reload of the current page.
Uri? reloadTarget({
  required Uri? failedUrl,
  required bool hasLoaded,
  required Uri homeUrl,
}) => failedUrl ?? (hasLoaded ? null : homeUrl);

/// Whether this error should cover the page with the "load failed" view.
bool isPageLoadFailure(
  WebResourceErrorType type, {
  required bool isMainFrame,
}) => isMainFrame && _networkFailures.contains(type);

/// The user-facing reason for a load failure.
String loadFailureMessage(WebResourceErrorType type) {
  if (type == WebResourceErrorType.NOT_CONNECTED_TO_INTERNET ||
      type == WebResourceErrorType.DATA_NOT_ALLOWED ||
      type == WebResourceErrorType.INTERNATIONAL_ROAMING_OFF) {
    return '沒有網路連線，連上之後再試一次。';
  }
  if (_certificateFailures.contains(type)) {
    return '連線不安全。如果連的是學校或店家的 Wi-Fi，先在 Safari 登入 Wi-Fi，或確認手機時間正確。';
  }
  if (type == WebResourceErrorType.TIMEOUT) {
    return '網路太慢，IG 沒有回應。';
  }
  return 'IG 暫時連不上，可能是網路不穩。';
}

/// Covers the web view when the page failed to load.
class LoadFailureView extends StatelessWidget {
  const LoadFailureView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text('IG 載入失敗', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重新載入'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
