import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:invoiceninja_flutter/.env.dart';
import 'package:invoiceninja_flutter/constants.dart';
import 'package:invoiceninja_flutter/redux/app/app_actions.dart';
import 'package:invoiceninja_flutter/redux/ui/ui_actions.dart';
import 'package:invoiceninja_flutter/ui/auth/login_vm.dart';
import 'package:invoiceninja_flutter/utils/formatting.dart';
import 'package:redux/redux.dart';
import 'package:invoiceninja_flutter/redux/auth/auth_actions.dart';
import 'package:invoiceninja_flutter/redux/app/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:invoiceninja_flutter/data/repositories/auth_repository.dart';

List<Middleware<AppState>> createStoreAuthMiddleware([
  AuthRepository repository = const AuthRepository(),
]) {
  final userLogout = _createUserLogout();
  final loginRequest = _createLoginRequest(repository);
  final signUpRequest = _createSignUpRequest(repository);
  final oauthRequest = _createOAuthRequest(repository);
  final refreshRequest = _createRefreshRequest(repository);
  final recoverRequest = _createRecoverRequest(repository);

  return [
    TypedMiddleware<AppState, UserLogout>(userLogout),
    TypedMiddleware<AppState, UserLoginRequest>(loginRequest),
    TypedMiddleware<AppState, UserSignUpRequest>(signUpRequest),
    TypedMiddleware<AppState, OAuthLoginRequest>(oauthRequest),
    TypedMiddleware<AppState, RefreshData>(refreshRequest),
    TypedMiddleware<AppState, RecoverPasswordRequest>(recoverRequest),
  ];
}

void _saveAuthLocal(
    {String email = '', String url = '', String secret = ''}) async {
  if (kIsWeb) {
    return;
  }

  final SharedPreferences prefs = await SharedPreferences.getInstance();
  prefs.setString(kSharedPrefEmail, email ?? '');
  prefs.setString(kSharedPrefUrl, formatApiUrl(url));
  prefs.setString(kSharedPrefSecret, secret);
}

void _loadAuthLocal(Store<AppState> store) async {
  if (kIsWeb) {
    return;
  }

  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final String email = kReleaseMode
      ? (prefs.getString(kSharedPrefEmail) ?? '')
      : Config.TEST_EMAIL;
  final String url = formatApiUrl(prefs.getString(kSharedPrefUrl) ?? '');
  final String secret = prefs.getString(kSharedPrefSecret) ?? '';

  store.dispatch(UserLoginLoaded(email, url, secret));

  store.dispatch(UserSettingsChanged(
    enableDarkMode: prefs.getBool(kSharedPrefEnableDarkMode) ?? true,
    accentColor: prefs.getString(kSharedPrefAccentColor) ?? kDefaultAccentColor,
    emailPayment: prefs.getBool(kSharedPrefEmailPayment) ?? false,
    requireAuthentication:
        prefs.getBool(kSharedPrefRequireAuthentication) ?? false,
    autoStartTasks: prefs.getBool(kSharedPrefAutoStartTasks) ?? false,
    addDocumentsToInvoice:
        prefs.getBool(kSharedPrefAddDocumentsToInvoice) ?? false,
  ));
}

Middleware<AppState> _createUserLogout() {
  return (Store<AppState> store, dynamic dynamicAction, NextDispatcher next) {
    final action = dynamicAction as UserLogout;

    next(action);

    _loadAuthLocal(store);

    store.dispatch(UpdateCurrentRoute(LoginScreen.route));

    Navigator.of(action.context).pushNamedAndRemoveUntil(
        LoginScreen.route, (Route<dynamic> route) => false);
  };
}

Middleware<AppState> _createLoginRequest(AuthRepository repository) {
  return (Store<AppState> store, dynamic dynamicAction, NextDispatcher next) {
    final action = dynamicAction as UserLoginRequest;

    repository
        .login(
            email: action.email,
            password: action.password,
            url: action.url,
            secret: action.secret,
            platform: action.platform,
            oneTimePassword: action.oneTimePassword)
        .then((data) {
      _saveAuthLocal(
        email: action.email,
        secret: action.secret,
        url: action.url,
      );
      store.dispatch(
          LoadAccountSuccess(completer: action.completer, loginResponse: data));
    }).catchError((Object error) {
      print(error);
      var message = error.toString();
      if (message.toLowerCase().contains('no host specified')) {
        message = 'Please check the URL is correct';
      } else if (message.toLowerCase().contains('credentials')) {
        message += ', please confirm your credentials in the web app';
      } else if (message.contains('404')) {
        message += ', you may need to add /public to the URL';
      }
      store.dispatch(UserLoginFailure(message));
      if (action.completer != null) {
        action.completer.completeError(error);
      }
    });

    next(action);
  };
}

Middleware<AppState> _createSignUpRequest(AuthRepository repository) {
  return (Store<AppState> store, dynamic dynamicAction, NextDispatcher next) {
    final action = dynamicAction as UserSignUpRequest;

    repository
        .signUp(
      email: action.email,
      password: action.password,
      platform: action.platform,
      firstName: action.firstName,
      lastName: action.lastName,
    )
        .then((data) {
      _saveAuthLocal(email: action.email, secret: '', url: '');

      store.dispatch(
          LoadAccountSuccess(completer: action.completer, loginResponse: data));
    }).catchError((Object error) {
      print(error);
      store.dispatch(UserLoginFailure(error));
      if (action.completer != null) {
        action.completer.completeError(error);
      }
    });

    next(action);
  };
}

Middleware<AppState> _createOAuthRequest(AuthRepository repository) {
  return (Store<AppState> store, dynamic dynamicAction, NextDispatcher next) {
    final action = dynamicAction as OAuthLoginRequest;

    repository
        .oauthLogin(
            token: action.token,
            url: action.url,
            secret: action.secret,
            platform: action.platform)
        .then((data) {
      _saveAuthLocal(
        email: action.email,
        secret: action.secret,
        url: action.url,
      );

      store.dispatch(
          LoadAccountSuccess(completer: action.completer, loginResponse: data));
    }).catchError((Object error) {
      print(error);
      store.dispatch(UserLoginFailure(error.toString()));
      if (action.completer != null) {
        action.completer.completeError(error);
      }
    });

    next(action);
  };
}

Middleware<AppState> _createRefreshRequest(AuthRepository repository) {
  return (Store<AppState> store, dynamic dynamicAction,
      NextDispatcher next) async {
    final action = dynamicAction as RefreshData;

    next(action);

    _loadAuthLocal(store);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String url =
        formatApiUrl(prefs.getString(kSharedPrefUrl) ?? Config.TEST_URL);
    final String token = prefs.getString(kSharedPrefToken);

    repository
        .refresh(url: url, token: token, platform: action.platform)
        .then((data) {
      store.dispatch(LoadAccountSuccess(
          completer: action.completer,
          loginResponse: data,
          loadCompanies: action.loadCompanies));
    }).catchError((Object error) {
      print(error);
      store.dispatch(UserLoginFailure(error.toString()));
      if (action.completer != null) {
        action.completer.completeError(error);
      }
    });
  };
}

Middleware<AppState> _createRecoverRequest(AuthRepository repository) {
  return (Store<AppState> store, dynamic dynamicAction, NextDispatcher next) {
    final action = dynamicAction as RecoverPasswordRequest;

    repository
        .recoverPassword(
      email: action.email,
      url: action.url,
      secret: action.secret,
    )
        .then((data) {
      store.dispatch(RecoverPasswordSuccess());
      action.completer.complete(null);
    }).catchError((Object error) {
      if (action.completer != null) {
        store.dispatch(RecoverPasswordFailure(error.toString()));
        action.completer.completeError(error);
      }
    });

    next(action);
  };
}
