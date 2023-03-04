import 'dart:async';
import 'dart:convert';
import 'package:chat_app_class/main.dart';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:chat_app_class/screens/login_screen.dart';
import 'package:chat_app_class/screens/notifications_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../constants.dart';

class ChatScreen extends StatefulWidget {
  static const id = 'chatScreen';
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _firebaseAuth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  late User user;
  dynamic messages;
  String? typingDocId;
  Timer? timer;
  List<RemoteNotification?> notifications = [];
  TextEditingController controller = TextEditingController();

  String token = '';
  void getCurrentUser() {
    user = _firebaseAuth.currentUser!;
  }

  void getNotifications() {
    //foreground messages(notifications)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        setState(() {
          notifications.add(message.notification);
        });
        print(
            'Message also contained a notification: ${message.notification!.title}');
      }
    });
  }

  void sendNotification(String title, String body) async {
    http.Response response = await http.post(
        Uri.parse(
            'https://fcm.googleapis.com/v1/projects/chat-app-flutter-118ea/messages:send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token'
        },
        body: jsonEncode({
          'message': {
            'topic': 'breaking_news',
            //'token': fcmToken,
            'notification': {'body': body, 'title': title}
          }
        }));
    print('response body: ${response.body}');
  }

  Future<AccessToken> getAccessToken() async {
    // here i remove json file because security
    final serviceAccount = await rootBundle.loadString('');
    final data = await json.decode(serviceAccount);
    print(data);
    final accountCredentials = ServiceAccountCredentials.fromJson({
      "private_key_id": data['private_key_id'],
      "private_key": data['private_key'],
      "client_email": data['client_email'],
      "client_id": data['client_id'],
      "type": data['type'],
    });
    final scopes = ["https://www.googleapis.com/auth/firebase.messaging"];
    final AuthClient authClient = await clientViaServiceAccount(
      accountCredentials,
      scopes,
    )
      ..close(); // Remember to close the client when you are finished with it.

    print(authClient.credentials.accessToken);

    return authClient.credentials.accessToken;
  }

  @override
  void initState() {
    getCurrentUser();
    getNotifications();
    getAccessToken().then((value) => token = value.data);
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          leading: null,
          actions: <Widget>[
            Stack(
              children: [
                IconButton(
                    icon: const Icon(Icons.notifications),
                    onPressed: () {
                      // arguments parameter means another way to send data via navigator
                      Navigator.pushNamed(context, NotificationsScreen.id,
                              arguments: notifications)
                          .then((value) => setState(() {
                                notifications.clear();
                              }));
                    }),
                notifications.isNotEmpty
                    ? Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        margin: EdgeInsets.all(8),
                        child: Text(
                          '${notifications.length}',
                          style: TextStyle(fontSize: 10),
                        ),
                        decoration: BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle),
                      )
                    : SizedBox()
              ],
            ),
            IconButton(
                icon: Icon(Icons.logout),
                onPressed: () {
                  _firebaseAuth.signOut();
                  Navigator.pushNamedAndRemoveUntil(
                      context, LoginScreen.id, (route) => false);
                }),
          ],
          title: Text('⚡️Chat'),
          backgroundColor: Colors.lightBlueAccent,
        ),
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              StreamBuilder(
                  stream: _firestore.collection('typing_users').snapshots(),
                  builder: (context, snapshot) {
                    //snapshot is a piece of returned data from firebase
                    if (snapshot.hasData) {
                      List<dynamic> users = snapshot.data!.docs;

                      return ListView.builder(
                          shrinkWrap: true,
                          reverse: true,
                          itemCount: users.length,
                          itemBuilder: (context, index) {
                            // just add other typing users, not me.
                            if (users[index]['user'] != user.email) {
                              return Container(
                                  color: Colors.amberAccent,
                                  child: Text('${users[index]['user']}'));
                            }
                            return SizedBox();
                          });
                    }
                    return const SizedBox();
                  }),
              StreamBuilder(
                  stream: _firestore
                      .collection('messages')
                      .orderBy('time', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    //snapshot is a piece of returned data from firebase
                    if (snapshot.hasData) {
                      List<dynamic> messages = snapshot.data!.docs;

                      return Expanded(
                        child: ListView.builder(
                            shrinkWrap: true,
                            reverse: true,
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              return MessageBubble(
                                messages: messages,
                                index: index,
                                sender: messages[index]['sender'],
                                isMe: messages[index]['sender'] == user.email,
                              );
                            }),
                      );
                    }
                    return const Text('Loading data...');
                  }),
              Container(
                decoration: kMessageContainerDecoration,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: kMessageTextFieldDecoration,
                        onChanged: (value) async {
                          //So that the user is not added once a letter, for example, is written incorrectly
                          // if value of timer is active(true), then cancel it and start new timer, else timer equal null, then replace it with false value to avoid an exception.
                          if (timer?.isActive ?? false) timer?.cancel();
                          timer = Timer(Duration(milliseconds: 500), () async {
                            if (value.isNotEmpty) {
                              if (typingDocId == null) {
                                final ref = await _firestore
                                    .collection('typing_users')
                                    .add({'user': user.email});
                                typingDocId = ref.id;
                              }
                            } else if (controller.text.isEmpty) {
                              _firestore
                                  .collection('typing_users')
                                  .doc(typingDocId)
                                  .delete();
                              typingDocId = null;
                            }
                          });
                        },
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        if (controller.text.isNotEmpty) {
                          _firestore.collection('messages').add({
                            'text': controller.text,
                            'sender': user.email,
                            'time': DateTime.now()
                          });
                          sendNotification('new message from ${user.email}',
                              controller.text);
                          controller.clear();
                          if (typingDocId != null) {
                            _firestore
                                .collection('typing_users')
                                .doc(typingDocId)
                                .delete();
                            typingDocId = null;
                          }
                        }
                      },
                      child: Text(
                        'Send',
                        style: kSendButtonTextStyle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ));
  }
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    Key? key,
    required this.messages,
    required this.index,
    required this.sender,
    required this.isMe,
  }) : super(key: key);

  final List messages;
  final int index;
  final String sender;
  final bool isMe;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Text(sender),
          SizedBox(
            height: 8,
          ),
          Material(
              borderRadius: isMe
                  ? BorderRadius.only(
                      topRight: Radius.circular(10),
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    )
                  : BorderRadius.only(
                      topLeft: Radius.circular(10),
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
              color: isMe ? Colors.blueAccent : Colors.lightBlueAccent,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  '${messages[index]['text']}',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
              ))
        ],
      ),
    );
  }
}
