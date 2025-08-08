import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

// 【第 1 步：匯入設定檔】
import 'config.dart'; 

// --- 資料模型 ---
class LocationTarget {
  final String name;
  final double latitude;
  final double longitude;

  LocationTarget({required this.name, required this.latitude, required this.longitude});

  factory LocationTarget.fromJson(Map<String, dynamic> json) {
    return LocationTarget(
      name: json['name'],
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '使用者定位 App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          foregroundColor: Colors.black87,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: const LoginPage(),
    );
  }
}

// ====================================================================
// 登入頁面 Widget
// ====================================================================
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController(text: 'it007');
  final _passwordController = TextEditingController();
  String _errorMessage = '';
  bool _isLoading = false;

  Future<void> _login() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = '帳號和密碼不能為空');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final String username = _usernameController.text;
    final String password = _passwordController.text;
    
    // 【第 2 步：移除舊的 IP 判斷邏輯】
    // final String apiBaseUrl = Platform.isAndroid ? 'http://10.0.2.2:8080' : 'http://localhost:8080'; // <- 已刪除

    final String basicAuthHeader = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';

    try {
      // 【第 3 步：使用從 config.dart 匯入的 apiBaseUrl】
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/location/all-targets'),
        headers: {'Authorization': basicAuthHeader},
      ).timeout(const Duration(seconds: 10));

      if (mounted) {
        if (response.statusCode == 200) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => UserHomePage(
                title: '使用者定位簽到',
                username: username,
                password: password,
              ),
            ),
          );
        } else if (response.statusCode == 401) {
          setState(() => _errorMessage = '登入失敗：帳號或密碼錯誤');
        } else {
          setState(() => _errorMessage = '登入失敗：伺服器錯誤 ${response.statusCode}');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = '登入失敗：無法連線至伺服器');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登入')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('簽到系統', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 40),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: '帳號',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                keyboardType: TextInputType.text,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: '密碼',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20.0),
                  child: Text(_errorMessage, style: const TextStyle(color: Colors.red)),
                ),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _login,
                      child: const Text('登入'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}


// ====================================================================
// 簽到主頁 Widget (UserHomePage)
// ====================================================================
class UserHomePage extends StatefulWidget {
  final String username;
  final String password;

  const UserHomePage({
    super.key, 
    required this.title,
    required this.username,
    required this.password,
  });
  
  final String title;

  @override
  State<UserHomePage> createState() => _UserHomePageState();
}

class _UserHomePageState extends State<UserHomePage> {
  Position? _currentPosition;
  String _statusMessage = '正在從伺服器獲取地點列表...';
  bool _isLoading = false;
  bool _isFetchingLocations = true;

  List<LocationTarget> _locations = [];
  LocationTarget? _selectedLocation;

  // 【第 2 步：移除舊的 IP 判斷邏輯】
  // final String _apiBaseUrl = Platform.isAndroid ? 'http://10.0.2.2:8080' : 'http://localhost:8080'; // <- 已刪除
  
  String get _basicAuthHeader {
    return 'Basic ${base64Encode(utf8.encode('${widget.username}:${widget.password}'))}';
  }

  @override
  void initState() {
    super.initState();
    _fetchLocationTargets();
  }

  Future<void> _fetchLocationTargets() async {
    try {
      // 【第 3 步：使用從 config.dart 匯入的 apiBaseUrl】
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/location/all-targets'),
        headers: {'Authorization': _basicAuthHeader},
      ).timeout(const Duration(seconds: 10));

      if (mounted) {
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
          setState(() {
            _locations = data.map((item) => LocationTarget.fromJson(item)).toList();
            if (_locations.isNotEmpty) {
              _selectedLocation = _locations.first;
              _statusMessage = '請選擇地點後開始簽到';
            } else {
              _statusMessage = '伺服器沒有提供任何簽到地點';
            }
          });
        } else {
          setState(() => _statusMessage = '獲取地點失敗：伺服器錯誤 ${response.statusCode}');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _statusMessage = '獲取地點失敗：無法連線至伺服器');
    } finally {
      if (mounted) setState(() => _isFetchingLocations = false);
    }
  }

  Future<bool> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _statusMessage = '請開啟裝置的定位服務');
      return false;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _statusMessage = '您已拒絕定位權限，無法簽到');
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _statusMessage = '定位權限已被永久拒絕，請至系統設定中手動開啟');
      return false;
    } 
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
      );
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _statusMessage = '位置獲取成功！準備簽到...';
        });
      }
      return true;
    } catch (e) {
      if (mounted) setState(() => _statusMessage = '獲取位置失敗: $e');
      return false;
    }
  }

  Future<void> _sendArrivalRequest() async {
    if (_currentPosition == null || _selectedLocation == null) {
      if (mounted) setState(() => _statusMessage = '錯誤：缺少位置或目標地點');
      return;
    }
    // 【第 3 步：使用從 config.dart 匯入的 apiBaseUrl】
    final String apiUrl = '$apiBaseUrl/api/location/check-in';

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': _basicAuthHeader,
        },
        body: json.encode({
          'userId': widget.username,
          'locationName': _selectedLocation!.name,
          'latitude': _currentPosition!.latitude,
          'longitude': _currentPosition!.longitude,
        }),
      ).timeout(const Duration(seconds: 15));

      if (mounted) {
        final responseBody = json.decode(utf8.decode(response.bodyBytes));
        final message = responseBody['message'] ?? '伺服器未提供訊息';

        if (response.statusCode == 200) {
          setState(() => _statusMessage = '簽到成功：$message');
        } else {
          setState(() => _statusMessage = '簽到失敗：$message');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _statusMessage = '呼叫簽到 API 失敗: $e');
    }
  }

  void _handleCheckIn() async {
    if (_isLoading) return;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _statusMessage = '正在獲取您的位置...';
        _currentPosition = null;
      });
    }
    final bool gotLocation = await _getCurrentLocation();
    if (!gotLocation) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    await _sendArrivalRequest();
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          _isFetchingLocations
              ? const Padding(
                  padding: EdgeInsets.only(right: 20.0),
                  child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
                )
              : _locations.isNotEmpty
                  ? Container(
                      margin: const EdgeInsets.only(right: 10.0),
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(8.0)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<LocationTarget>(
                          value: _selectedLocation,
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.deepPurple),
                          onChanged: (LocationTarget? newValue) {
                            setState(() {
                              _selectedLocation = newValue;
                              _statusMessage = '已選擇地點：${newValue?.name}';
                            });
                          },
                          items: _locations.map<DropdownMenuItem<LocationTarget>>((LocationTarget location) {
                            return DropdownMenuItem<LocationTarget>(value: location, child: Text(location.name, style: const TextStyle(color: Colors.black87)));
                          }).toList(),
                        ),
                      ),
                    )
                  : const Padding(
                      padding: EdgeInsets.only(right: 16.0),
                      child: Icon(Icons.error_outline, color: Colors.red),
                    ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _buildInfoCard(
                icon: Icons.flag,
                title: '目標簽到點',
                content: _selectedLocation?.name ?? '正在載入地點...',
                subtitle: _selectedLocation != null ? '緯度: ${_selectedLocation!.latitude}, 經度: ${_selectedLocation!.longitude}' : '',
              ),
              const SizedBox(height: 16),
              _buildInfoCard(
                icon: Icons.location_pin,
                title: '您目前的位置',
                content: _currentPosition == null ? '尚未取得位置' : '緯度: ${_currentPosition!.latitude.toStringAsFixed(5)}\n經度: ${_currentPosition!.longitude.toStringAsFixed(5)}',
              ),
              const SizedBox(height: 16),
              _buildInfoCard(
                icon: Icons.info_outline,
                title: '處理狀態',
                content: _statusMessage,
              ),
              const SizedBox(height: 48),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton.icon(
                      onPressed: _handleCheckIn,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('點我簽到'),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({required IconData icon, required String title, required String content, String? subtitle}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 20, thickness: 1),
            Text(content, style: TextStyle(fontSize: 16, color: Colors.grey[800], height: 1.5), textAlign: TextAlign.center),
            if (subtitle != null && subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600]), textAlign: TextAlign.center),
              ),
          ],
        ),
      ),
    );
  }
}
