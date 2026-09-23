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

/// Some platforms deliver the launch link through both getInitialLink
/// and the stream, moments apart. Drops exactly that: the first repeat
/// of the last handled link within [window]. The same link tapped again
/// later (e.g. after backing out of activation) is handled again.
class LinkDeduper {
  LinkDeduper({this.window = const Duration(seconds: 2)});

  final Duration window;
  Uri? _last;
  DateTime? _lastAt;
  bool _dropped = false;

  bool shouldHandle(Uri u, DateTime now) {
    if (!_dropped &&
        u == _last &&
        _lastAt != null &&
        now.difference(_lastAt!) < window) {
      _dropped = true;
      return false;
    }
    _last = u;
    _lastAt = now;
    _dropped = false;
    return true;
  }
}

/// Delivers invite links to [listen]'s callback: the link that cold-
/// started the app (getInitialLink) and any opened while it runs.
class DeepLinkService {
  final _links = AppLinks();
  StreamSubscription<Uri>? _sub;
  final _deduper = LinkDeduper();

  void listen(void Function(ActivationArgs) onActivation) {
    _links.getInitialLink().then((u) {
      if (u != null) _handle(u, onActivation);
    }).catchError((_) {});
    _sub = _links.uriLinkStream
        .listen((u) => _handle(u, onActivation), onError: (_) {});
  }

  void _handle(Uri u, void Function(ActivationArgs) cb) {
    final a = parseActivationLink(u);
    if (a == null) return;
    if (!_deduper.shouldHandle(u, DateTime.now())) return;
    cb(a);
  }

  void dispose() => _sub?.cancel();
}
