import 'dart:async';

import 'package:app_links/app_links.dart';

/// Company code + one-time token carried by an invite link.
class ActivationArgs {
  final String companyCode;
  final String token;
  const ActivationArgs(this.companyCode, this.token);
}

/// Parses `omnihr://activate?c=<company>&t=<token>`; null for any other
/// link or when either parameter is missing/empty.
ActivationArgs? parseActivationLink(Uri uri) {
  if (uri.scheme != 'omnihr' || uri.host != 'activate') return null;
  final c = uri.queryParameters['c'], t = uri.queryParameters['t'];
  if (c == null || c.isEmpty || t == null || t.isEmpty) return null;
  return ActivationArgs(c, t);
}

/// Delivers invite links to [listen]'s callback: the link that cold-
/// started the app (getInitialLink) and any opened while it runs.
class DeepLinkService {
  final _links = AppLinks();
  StreamSubscription<Uri>? _sub;

  /// Some platforms deliver the launch link through both getInitialLink
  /// and the stream; the same link is handled only once.
  Uri? _lastHandled;

  void listen(void Function(ActivationArgs) onActivation) {
    _links.getInitialLink().then((u) {
      if (u != null) _handle(u, onActivation);
    }).catchError((_) {});
    _sub = _links.uriLinkStream
        .listen((u) => _handle(u, onActivation), onError: (_) {});
  }

  void _handle(Uri u, void Function(ActivationArgs) cb) {
    if (u == _lastHandled) return;
    final a = parseActivationLink(u);
    if (a == null) return;
    _lastHandled = u;
    cb(a);
  }

  void dispose() => _sub?.cancel();
}
