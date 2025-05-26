import 'dart:io'; // For Platform.isWindows, Platform.isLinux, Platform.isMacOS
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // For FFI initialization
import 'screens/home_screen.dart';

Future<void> main() async { // main needs to be async for ensureInitialized
  WidgetsFlutterBinding.ensureInitialized(); // Ensure bindings are initialized

  // Initialize FFI for sqflite if on desktop
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MapTool',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
