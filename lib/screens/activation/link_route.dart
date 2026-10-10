import 'package:flutter/widgets.dart';

import '../../services/deep_link_service.dart';
import 'activation_screen.dart';
import 'add_phone_screen.dart';

/// The screen an Omni HR link or QR opens: Add this phone for an
/// add-phone pair (`k=add`, connector 2.62.0+), else the invite
/// activation. Every entry point (the deep link in main.dart and the
/// scanners on the company-code, login and activation screens) goes
/// through here, so an add-phone token is never posted to
/// `auth/activate`.
Widget screenForActivationLink(ActivationArgs a) => a.isAddPhone
    ? AddPhoneScreen(
        companyCode: a.companyCode, token: a.token, login: a.login)
    : ActivationScreen(
        companyCode: a.companyCode, token: a.token, login: a.login);
