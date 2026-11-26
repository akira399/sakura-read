import 'dart:async';

import 'package:flutter/foundation.dart';

/// 小樱桌宠 2.0 实时情绪枚举（驱动 LiveSakuraPet 表情与微动效）。
enum PetLiveMood {
  idle,
  reading,
  happy,
  shy,
  sleepy,
  pouting,
  thinking,
  speaking,
}

/// 轻量级情绪事件总线：将 AI 思考/回复状态与阅读里程碑实时桥接到桌宠表情。
///
/// 本身是 `ValueNotifier<PetLiveMood>`，可直接在 `ValueListenableBuilder` 中订阅。
class PetMoodBus extends ValueNotifier<PetLiveMood> {
  PetMoodBus([super.initial = PetLiveMood.idle]);

  Timer? _autoResetTimer;
  int _sequence = 0;

  /// 最近一次伴随情绪附带的短台词（可为空）。
  final ValueNotifier<String?> latestLine = ValueNotifier<String?>(null);

  /// 事件序号：同一种情绪重复触发时也会递增，便于 UI 触发飘心/星光脉冲。
  int get sequence => _sequence;

  /// 切换情绪，可选附带短台词与自动回落时长。
  void setMood(PetLiveMood mood, {String? line, Duration? autoResetAfter}) {
    _autoResetTimer?.cancel();
    _autoResetTimer = null;
    _sequence++;
    if (line != null) {
      latestLine.value = line;
    }
    if (value != mood) {
      value = mood;
    } else {
      notifyListeners();
    }
    if (autoResetAfter != null) {
      _autoResetTimer = Timer(autoResetAfter, () {
        _autoResetTimer = null;
        if (value == mood) {
          value = PetLiveMood.idle;
        }
      });
    }
  }

  /// AI 正在思考 / 等待首字流式返回。
  void onAiThinking({String? line}) {
    setMood(
      PetLiveMood.thinking,
      line: line,
      autoResetAfter: const Duration(seconds: 60),
    );
  }

  /// AI 正在流式吐字回答。
  void onAiSpeaking({String? line}) {
    setMood(
      PetLiveMood.speaking,
      line: line,
      autoResetAfter: const Duration(seconds: 60),
    );
  }

  /// AI 对话或分析结束，回归常态。
  void onAiIdle() {
    if (value == PetLiveMood.thinking || value == PetLiveMood.speaking) {
      _autoResetTimer?.cancel();
      _autoResetTimer = null;
      value = PetLiveMood.idle;
    }
  }

  /// 阅读里程碑达成（如读完一章、获得点心、达成连续阅读）。
  void onReadingMilestone(String message) {
    setMood(
      PetLiveMood.happy,
      line: message,
      autoResetAfter: const Duration(seconds: 4),
    );
  }

  /// 进入或离开安静陪读状态。
  void onReadingState(bool reading) {
    if (reading) {
      setMood(PetLiveMood.reading);
    } else if (value == PetLiveMood.reading) {
      setMood(PetLiveMood.idle);
    }
  }

  /// 复位到常态并取消任何挂起定时器（测试清理亦可调用）。
  void reset() {
    _autoResetTimer?.cancel();
    _autoResetTimer = null;
    latestLine.value = null;
    value = PetLiveMood.idle;
  }

  @override
  void dispose() {
    _autoResetTimer?.cancel();
    _autoResetTimer = null;
    latestLine.dispose();
    super.dispose();
  }
}

/// 全局共享桌宠情绪总线。
final PetMoodBus kPetMoodBus = PetMoodBus();
