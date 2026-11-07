import 'package:sqlite3/sqlite3.dart';

abstract class Migration {
  final int version;
  final String name;

  const Migration({required this.version, required this.name});

  void up(Database db);
  void down(Database db);
}
