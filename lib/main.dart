import 'package:flutter/material.dart';
import 'package:ishara/constants/app_constants.dart';
import 'package:ishara/controllers/camera_controller.dart';
import 'package:ishara/controllers/ishara_test_controller.dart';
import 'package:ishara/models/camera_state_model.dart';
import 'package:ishara/providers/vision_detection_provider.dart';
import 'package:ishara/services/camera_service.dart';
import 'package:ishara/services/hand_detection_service.dart';
import 'package:ishara/services/vision_detection_service.dart';
import 'package:ishara/theme/app_theme.dart';
import 'package:ishara/views/home_view.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IsharaApp());
}

class IsharaApp extends StatefulWidget {
  const IsharaApp({super.key});

  @override
  State<IsharaApp> createState() => _IsharaAppState();
}

class _IsharaAppState extends State<IsharaApp> {
  late final CameraService _cameraService;
  late final HandDetectionService _handDetectionService;
  late final VisionDetectionService _visionDetectionService;
  late final VisionDetectionProvider _visionDetectionProvider;
  late final IsharaTestController _isharaTestController;

  @override
  void initState() {
    super.initState();
    _cameraService = CameraService();
    _handDetectionService = HandDetectionService();
    _visionDetectionService = VisionDetectionService();
    _visionDetectionProvider = VisionDetectionProvider(_visionDetectionService);
    _isharaTestController = IsharaTestController(_visionDetectionService);

    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      await _handDetectionService.initialize();
    } catch (e) {
      debugPrint('[Main] ⚠️ HandDetectionService init error: $e');
    }

    try {
      await _visionDetectionProvider.initialize();
    } catch (e) {
      debugPrint('[Main] ⚠️ VisionDetectionProvider init error: $e');
    }
  }

  @override
  void dispose() {
    _isharaTestController.dispose();
    _visionDetectionProvider.dispose();
    _handDetectionService.dispose();
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CameraStateModel()),
        ChangeNotifierProvider(
          create: (_) => CameraProvider(_cameraService, _handDetectionService),
        ),
        ChangeNotifierProvider.value(value: _visionDetectionProvider),
        ChangeNotifierProvider.value(value: _isharaTestController),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        builder: (context, child) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const HomeView(),
      ),
    );
  }
}
