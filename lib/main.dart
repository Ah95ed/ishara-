import 'package:flutter/material.dart';
import 'package:ishara/constants/app_constants.dart';
import 'package:ishara/controllers/camera_controller.dart';
import 'package:ishara/controllers/gloss_controller.dart';
import 'package:ishara/controllers/sign_controller.dart';
import 'package:ishara/controllers/speech_controller.dart';
import 'package:ishara/controllers/translation_controller.dart';
import 'package:ishara/models/camera_state_model.dart';
import 'package:ishara/repositories/sign_repository.dart';
import 'package:ishara/services/ai_service.dart';
import 'package:ishara/services/camera_service.dart';
import 'package:ishara/services/gloss_model_service.dart';
import 'package:ishara/services/hand_detection_service.dart';
import 'package:ishara/services/local_memory_service.dart';
import 'package:ishara/services/local_model_service.dart';
import 'package:ishara/services/ml_service.dart';
import 'package:ishara/services/speech_service.dart';
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
  late final SpeechService _speechService;
  late final LocalMemoryService _localMemoryService;
  late final MLService _mlService;
  late final SignRepository _signRepository;
  late final LocalModelService _localModelService;
  late final AIService _aiService;
  late final CameraService _cameraService;
  late final HandDetectionService _handDetectionService;
  late final GlossModelService _glossModelService;
  late final GlossController _glossController;
  late final SignProvider _signProvider;

  @override
  void initState() {
    super.initState();
    _speechService = SpeechService();
    _localMemoryService = LocalMemoryService();
    _mlService = MLService();
    _signRepository = SignRepository();
    _localModelService = LocalModelService();
    _aiService = GeminiAIService(apiKey: '');
    _cameraService = CameraService();
    _handDetectionService = HandDetectionService();
    _glossModelService = GlossModelService();
    _glossController = GlossController(_glossModelService);
    _signProvider = SignProvider(_mlService, _speechService);

    // ربط مستشعر استقرار الإشارة بالـ GlossController (Dual-Path)
    _signProvider.onStableSignDetected = (prediction) {
      _glossController.onStableSign(prediction);
    };
    _signProvider.onStabilityStateChanged = (state, label, confidence) {
      _glossController.updateStabilityState(state, label, confidence);
    };

    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      await _speechService.initialize();
      await _localMemoryService.initialize();
      await _signRepository.loadLabels();
      await _mlService.loadModel(_signRepository.labels);
      await _localModelService.initialize();
      await _handDetectionService.initialize();

      // تهيئة نموذج Gemma3 GGUF في الخلفية دون تجميد الواجهة
      _glossModelService.loadModel().catchError((_) => false);
    } catch (_) {}
  }

  @override
  void dispose() {
    _signProvider.dispose();
    _glossController.dispose();
    _glossModelService.dispose();
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
        ChangeNotifierProvider.value(value: _localMemoryService),
        ChangeNotifierProvider.value(value: _localModelService),
        ChangeNotifierProvider(
          create: (_) => TranslationController(
            _localMemoryService,
            _localModelService,
            _aiService,
            _speechService,
          ),
        ),
        ChangeNotifierProvider.value(value: _signProvider),
        ChangeNotifierProvider.value(value: _glossModelService),
        ChangeNotifierProvider.value(value: _glossController),
        ChangeNotifierProvider(create: (_) => SpeechProvider(_speechService)),
        Provider.value(value: _signRepository),
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
