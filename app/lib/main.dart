import 'package:flutter/material.dart';
import 'services/dataset_repository.dart';
import 'services/search_service.dart';
import 'services/audit_logger.dart';
import 'screens/dose_screen.dart';
import 'screens/cri_screen.dart';
import 'screens/search_screen.dart';
import 'screens/updates_screen.dart';
import 'screens/history_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final repository = DatasetRepository();
  await repository.initialize();

  final auditLogger = AuditLogger();
  await auditLogger.initialize();

  final searchService = SearchService();
  searchService.initializeWithBaseDrugs(repository.activeDrugs);

  runApp(VetifiApp(
    repository: repository,
    auditLogger: auditLogger,
    searchService: searchService,
  ));
}

class VetifiApp extends StatelessWidget {
  final DatasetRepository repository;
  final AuditLogger auditLogger;
  final SearchService searchService;

  const VetifiApp({
    super.key,
    required this.repository,
    required this.auditLogger,
    required this.searchService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vetifi Reference & Dose Calculator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF090D16), // Premium dark obsidian
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8), // Electric cyan
          secondary: Color(0xFF14B8A6), // Teal
          surface: Color(0xFF1E293B),
          background: Color(0xFF090D16),
          error: Color(0xFFEF4444),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          elevation: 0,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.2,
            color: Colors.white,
          ),
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      home: MainShell(
        repository: repository,
        auditLogger: auditLogger,
        searchService: searchService,
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  final DatasetRepository repository;
  final AuditLogger auditLogger;
  final SearchService searchService;

  const MainShell({
    super.key,
    required this.repository,
    required this.auditLogger,
    required this.searchService,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      DoseScreen(
        repository: widget.repository,
        auditLogger: widget.auditLogger,
      ),
      CriScreen(
        repository: widget.repository,
        auditLogger: widget.auditLogger,
      ),
      SearchScreen(
        searchService: widget.searchService,
      ),
      UpdatesScreen(
        repository: widget.repository,
      ),
      HistoryScreen(
        auditLogger: widget.auditLogger,
        repository: widget.repository,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        backgroundColor: const Color(0xFF0F172A),
        indicatorColor: const Color(0xFF0284C7).withOpacity(0.3),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calculate_outlined),
            selectedIcon: Icon(Icons.calculate, color: Color(0xFF38BDF8)),
            label: 'Dose',
          ),
          NavigationDestination(
            icon: Icon(Icons.water_drop_outlined),
            selectedIcon: Icon(Icons.water_drop, color: Color(0xFF14B8A6)),
            label: 'CRI Infusion',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search, color: Color(0xFF38BDF8)),
            label: 'Search (50k)',
          ),
          NavigationDestination(
            icon: Icon(Icons.security_outlined),
            selectedIcon: Icon(Icons.security, color: Color(0xFF38BDF8)),
            label: 'Updates',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history, color: Color(0xFF38BDF8)),
            label: 'History',
          ),
        ],
      ),
    );
  }
}
