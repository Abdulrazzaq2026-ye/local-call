import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'network_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    home: AppRoot(),
    debugShowCheckedModeBanner: false,
  ));
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  final NetworkService _networkService = NetworkService();
  String? myId;
  String? myName;
  String? myIp;
  bool isRegistered = false;

  Map<String, Peer> activePeers = {};

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndData();
  }

  Future<void> _checkPermissionsAndData() async {
    await [
      Permission.microphone,
      Permission.location,
      Permission.nearbyWifiDevices,
    ].request();

    final prefs = await SharedPreferences.getInstance();
    myId = prefs.getString('user_id');
    myName = prefs.getString('user_name');

    final info = NetworkInfo();
    myIp = await info.getWifiIP();

    if (myId != null && myName != null && myIp != null) {
      setState(() => isRegistered = true);
      _startServices();
    }
  }

  void _startServices() {
    _networkService.init(myId!, myName!, myIp!);

    _networkService.onPeersUpdated = (peers) {
      if (mounted) setState(() => activePeers = Map.from(peers));
    };

    _networkService.onIncomingCall = (callerName, callerIp) {
      _showIncomingCallDialog(callerName);
    };

    _networkService.onCallRejected = (msg) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    };

    _networkService.onCallAccepted = () {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showActiveCallDialog();
    };

    _networkService.onCallEnded = () {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('انتهت المكالمة')));
    };
  }

  void _showIncomingCallDialog(String callerName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('مكالمة واردة', textAlign: TextAlign.right),
        content: Text('$callerName يتصل بك...', textAlign: TextAlign.right),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              _networkService.rejectCall();
              Navigator.pop(ctx);
            },
            child: const Text('رفض', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              _networkService.acceptCall();
              Navigator.pop(ctx);
              _showActiveCallDialog();
            },
            child: const Text('رد', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showActiveCallDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('مكالمة جارية', textAlign: TextAlign.right),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.phone_in_talk, size: 50, color: Colors.green),
            SizedBox(height: 10),
            Text('جاري التحدث عبر الشبكة المحلية...', textAlign: TextAlign.center),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => _networkService.endCall(),
              child: const Text('إنهاء المكالمة', style: TextStyle(color: Colors.white)),
            ),
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    _networkService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isRegistered) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('إعداد الحساب المحلي'),
          centerTitle: true,
          backgroundColor: Colors.indigo,
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              const SizedBox(height: 10),
              TextField(
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  labelText: 'الاسم (مثل: الإدارة / فلان)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                onChanged: (val) => myName = val,
              ),
              const SizedBox(height: 15),
              TextField(
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  labelText: 'الرقم الداخلي (مثل: 101)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.tag),
                ),
                keyboardType: TextInputType.number,
                onChanged: (val) => myId = val,
              ),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
