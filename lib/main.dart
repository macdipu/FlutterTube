import 'package:flutter/material.dart';

import 'constants.dart';
import 'pages/home/home_page.dart';

void main(){
  print('🚀 main: App starting...');
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    print('🏗️ MyApp: Building app...');
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
      theme: ThemeData(
          brightness: Brightness.dark,
          primaryColor: PrimaryColor,
          scaffoldBackgroundColor: PrimaryColor
      ),
    );
  }
}