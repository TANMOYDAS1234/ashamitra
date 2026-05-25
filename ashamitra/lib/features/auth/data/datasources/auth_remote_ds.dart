import '../../../../core/services/api_service.dart';
import '../../../../core/constants/api_constants.dart';

// NOTE: This class is scaffolding from an earlier architecture and is not
// currently wired in. The active auth path goes through `AuthController` →
// `ApiService.sendOtp` / `ApiService.verifyOtp`. Kept as a placeholder if
// you want to reintroduce a repository layer later.
class AuthRemoteDs {
  final ApiService _api;
  AuthRemoteDs(this._api);

  Future<Map<String, dynamic>> sendOtp(String phone) async {
    final res = await _api.post(ApiConstants.authSendOtp, data: {'phone': phone});
    return res.data;
  }

  Future<Map<String, dynamic>> verifyOtp(String phone, String otp) async {
    final res = await _api.post(ApiConstants.authVerifyOtp, data: {'phone': phone, 'otp': otp});
    return res.data;
  }
}
