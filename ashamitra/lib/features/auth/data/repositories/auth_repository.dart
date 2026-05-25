import '../datasources/auth_remote_ds.dart';
import '../datasources/auth_local_ds.dart';
import '../models/user_model.dart';

class AuthRepository {
  final AuthRemoteDs _remote;
  final AuthLocalDs _local;
  AuthRepository(this._remote, this._local);

  Future<void> sendOtp(String phone) => _remote.sendOtp(phone);

  Future<UserModel> verifyOtp(String phone, String otp) async {
    final data = await _remote.verifyOtp(phone, otp);
    await _local.saveToken(data['token']);
    return UserModel.fromJson(data['user']);
  }

  bool get isLoggedIn => _local.getToken() != null;

  Future<void> logout() => _local.clear();
}
