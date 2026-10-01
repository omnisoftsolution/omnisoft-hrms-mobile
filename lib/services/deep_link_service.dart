import 'dart:async';

import 'package:app_links/app_links.dart';

/// Company code + one-time token (+ the app login, since 2.47) carried
/// by an invite link.
class ActivationArgs {
  final String companyCode;
  final String token;
  final String? login;
  const ActivationArgs(this.companyCode, this.token, {this.login});
}

/// Reads an Omni HR invite:
/// `omnihr://activate?c=<company>&t=<token>[&l=<login>]`, or (2.48+)
/// `https://<any host>/omni/activate#c=…&t=…[&l=…]` (also `?c=…` when a
/// mail app rewrote the `#`). The host is ignored on purpose: the tenant
/// server comes from the company code via the SaaS lookup, so a QR naming
/// another site cannot send the app anywhere. Null for anything else or
/// when c or t is missing/empty.
ActivationArgs? parseActivationLink(Uri uri) {
  try {
    final scheme = uri.scheme.toLowerCase();
    final Map<String, String> q;
    if (scheme == 'omnihr' && uri.host == 'activate') {
      q = uri.queryParameters;
    } else if (scheme == 'https' &&
        (uri.path == '/omni/activate' || uri.path == '/omni/activate/')) {
      q = uri.fragment.isNotEmpty
          ? Uri.splitQueryString(uri.fragment)
          : uri.queryParameters;
    } else {
      return null;
    }
    final c = q['c'], t = q['t'];
    if (c == null || c.isEmpty || t == null || t.isEmpty) return null;
    final l = q['l'];
    return ActivationArgs(c, t, login: (l == null || l.isEmpty) ? null : l);
  } on FormatException {
    return null;
  }
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

/// What a scanned QR turned out to be.
sealed class ScanResult {
  const ScanResult();
}

class InviteScan extends ScanResult {
  final ActivationArgs args;
  const InviteScan(this.args);
}

class NotInviteScan extends ScanResult {
  const NotInviteScan();
}

/// Classifies raw QR text for the invite scanner.
ScanResult classifyScan(String raw) {
  final uri = Uri.tryParse(raw.trim());
  final a = uri == null ? null : parseActivationLink(uri);
  return a == null ? const NotInviteScan() : InviteScan(a);
}
