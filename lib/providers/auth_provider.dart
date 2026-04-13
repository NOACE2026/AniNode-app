import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class AuthState {
  final bool isLoggedIn;
  final String? username;
  final bool isLoading;
  final String? errorMessage;

  AuthState({
    required this.isLoggedIn,
    this.username,
    this.isLoading = false,
    this.errorMessage,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    String? username,
    bool? isLoading,
    String? errorMessage,
  }) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      username: username ?? this.username,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  static const String _prefKey = 'aninode_auth_token';
  static const String _userKey = 'aninode_auth_user';
  
  static const String _validUser = 'invins2003';
  static const String _validPass1 = 'invinsmerepapa';
  static const String _validPass2 = 'InvinsExtreme';

  @override
  AuthState build() {
    // Start with loading state
    _loadAuthState();
    return AuthState(isLoggedIn: false, isLoading: true);
  }

  Future<void> _loadAuthState() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_prefKey);
    final user = prefs.getString(_userKey);
    
    if (token != null && user == _validUser) {
      state = AuthState(isLoggedIn: true, username: user);
    } else {
      state = AuthState(isLoggedIn: false);
    }
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    
    await Future.delayed(const Duration(milliseconds: 800));

    if (username == _validUser && (password == _validPass1 || password == _validPass2)) {
      final prefs = await SharedPreferences.getInstance();
      
      final token = sha256.convert(utf8.encode('$username$password${DateTime.now()}')).toString();
      
      await prefs.setString(_prefKey, token);
      await prefs.setString(_userKey, username);
      
      state = AuthState(isLoggedIn: true, username: username);
      return true;
    } else {
      state = AuthState(
        isLoggedIn: false, 
        errorMessage: 'Invalid username or password',
        isLoading: false,
      );
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    await prefs.remove(_userKey);
    state = AuthState(isLoggedIn: false);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
