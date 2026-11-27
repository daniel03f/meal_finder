import 'package:flutter/material.dart';
import 'src/presentation/screens/label_selection_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const MealFinderApp());
}

class MealFinderApp extends StatelessWidget {
  const MealFinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meal Finder',
      debugShowCheckedModeBanner: false,
      home: Home(),
    );
  }
}

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: LabelSelectionView(),
      ),
    );
  }
}
