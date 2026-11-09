import 'dart:async';
import 'dart:convert';
import 'dart:io';

class Peer {
  final String id;
  final String name;
  final String ip;
  final String status;
  DateTime lastSeen;

  Peer({
    required this.id,
    required this.name,
    required this.ip,
    required this.status,
    required this.lastSeen,
  });
}

class NetworkService {
  static const int broadcastPort = 45454;
  static const int signalingPort = 45455;

  RawDatagramSocket? _broadcastSocket;
  HttpServer? _signalingServer;
  Timer? _heartbeatTimer;
  Timer? _cleanupTimer;

  final Map<String, Peer> peers = {};
  String myId = '';
  String myName = '';
  String myIp = '';
  String status = 'available';
  String? currentPeerIp;

  Function(Map<String, Peer>)? onPeersUpdated;
  Function(String callerName, String callerIp)? onIncomingCall;
  Function()? onCallAccepted;
  Function(String reason)? onCallRejected;
  Function()? onCallEnded;

  void init(String id, String name, String ip) async {
    myId = id;
    myName = name;
    myIp = ip;

    await _initBroadcast();
    await _initSignaling();

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) => _sendBroadcast());
    _cleanupTimer = Timer.periodic(const Duration(seconds: 4), (_) => _cleanupPeers());
  }

  Future<void> _initBroadcast() async {
    try {
      _broadcastSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, broadcastPort);
      _broadcastSocket?.broadcastEnabled = true;
      _broadcastSocket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          Datagram? dg = _broadcastSocket?.receive();
          if (dg != null) {
            try {
              String msg = utf8.decode(dg.data);
              Map<String, dynamic> data = jsonDecode(msg);
              if (data['id'] != myId) {
                peers[data['id']] = Peer(
                  id: data['id'],
                  name: data['name'],
                  ip: dg.address.address,
                  status: data['status'] ?? 'available',
                  lastSeen: DateTime.now(),
                );
                onPeersUpdated?.call(peers);
              }
            } catch (_) {}
          }
        }
      });
    } catch (_) {}
  }

  void _sendBroadcast() {
    if (_broadcastSocket == null || myIp.isEmpty) return;
    try {
      final msg = jsonEncode({'id': myId, 'name': myName, 'status': status});
      _broadcastSocket?.send(utf8.encode(msg), InternetAddress('255.255.255.255'), broadcastPort);
    } catch (_) {}
  }

  void _cleanupPeers() {
    final now = DateTime.now();
    peers.removeWhere((key, peer) => now.difference(peer.lastSeen).inSeconds > 5);
    onPeersUpdated?.call(peers);
  }

  Future<void> _initSignaling() async {
    try {
      _signalingServer = await HttpServer.bind(InternetAddress.anyIPv4, signalingPort);
      _signalingServer?.listen((HttpRequest req) async {
        if (req.method == 'POST') {
          String body = await utf8.decodeStream(req);
          Map<String, dynamic> data = jsonDecode(body);
          String type = data['type'];
          String senderIp = req.connectionInfo?.remoteAddress.address ?? '';

          if (type == 'call_request') {
            if (status == 'busy') {
              req.response.write(jsonEncode({'response': 'busy'}));
            } else {
              currentPeerIp = senderIp;
              onIncomingCall?.call(data['name'], senderIp);
              req.response.write(jsonEncode({'response': 'ringing'}));
            }
          } else if (type == 'call_action') {
            if (data['action'] == 'accept') {
              status = 'busy';
              onCallAccepted?.call();
            } else if (data['action'] == 'reject') {
              _resetCall();
              onCallRejected?.call('تم رفض المكالمة');
            } else if (data['action'] == 'end') {
              _resetCall();
              onCallEnded?.call();
            }
            req.response.write(jsonEncode({'status': 'ok'}));
          }
          await req.response.close();
        }
      });
    } catch (_) {}
  }

  Future<void> call(String targetIp) async {
    currentPeerIp = targetIp;
    try {
      HttpClient client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);
      HttpClientRequest req = await client.post(targetIp, signalingPort, '/');
      req.write(jsonEncode({'type': 'call_request', 'name': myName}));
      HttpClientResponse res = await req.close();
      String reply = await utf8.decodeStream(res);
      Map<String, dynamic> data = jsonDecode(reply);

      if (data['response'] == 'busy') {
        _resetCall();
        onCallRejected?.call('الطرف الآخر مشغول');
      }
    } catch (_) {
      _resetCall();
      onCallRejected?.call('تعذر الاتصال بالطرف الآخر');
    }
  }

  void acceptCall() {
    if (currentPeerIp == null) return;
    status = 'busy';
    _sendAction(currentPeerIp!, 'accept');
  }

  void rejectCall() {
    if (currentPeerIp == null) return;
    _sendAction(currentPeerIp!, 'reject');
    _resetCall();
  }

  void endCall() {
    if (currentPeerIp != null) {
      _sendAction(currentPeerIp!, 'end');
    }
    _resetCall();
    onCallEnded?.call();
  }

  Future<void> _sendAction(String targetIp, String action) async {
    try {
      HttpClient client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      HttpClientRequest req = await client.post(targetIp, signalingPort, '/');
      req.write(jsonEncode({'type': 'call_action', 'action': action}));
      await req.close();
    } catch (_) {}
  }

  void _resetCall() {
    status = 'available';
    currentPeerIp = null;
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _cleanupTimer?.cancel();
    _broadcastSocket?.close();
    _signalingServer?.close();
  }
}
