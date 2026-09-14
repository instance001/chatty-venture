enum StoryActionKind { choose, freeform }

class StoryAction {
  const StoryAction({
    required this.kind,
    required this.target,
    required this.playerText,
  });
  final StoryActionKind kind;
  final String target;
  final String playerText;
}

class StoryChoice {
  const StoryChoice({required this.id, required this.label});
  final String id;
  final String label;
}

class StoryScene {
  const StoryScene({
    required this.id,
    required this.title,
    required this.description,
    required this.choices,
  });
  final String id;
  final String title;
  final String description;
  final List<StoryChoice> choices;
}

class StoryThread {
  const StoryThread({
    required this.id,
    required this.label,
    required this.status,
  });
  final String id;
  final String label;
  final String status;
}

class StoryState {
  const StoryState({
    required this.sceneId,
    required this.turn,
    required this.facts,
    required this.threads,
    required this.recap,
    this.ending,
  });
  factory StoryState.initial() => const StoryState(
    sceneId: 'lantern_quay',
    turn: 0,
    facts: {},
    threads: {},
    recap: [],
  );
  final String sceneId;
  final int turn;
  final Set<String> facts;
  final Map<String, StoryThread> threads;
  final List<String> recap;
  final String? ending;
  bool hasFact(String fact) => facts.contains(fact);
  StoryState copyWith({
    String? sceneId,
    int? turn,
    Set<String>? facts,
    Map<String, StoryThread>? threads,
    List<String>? recap,
    String? ending,
  }) => StoryState(
    sceneId: sceneId ?? this.sceneId,
    turn: turn ?? this.turn,
    facts: facts ?? this.facts,
    threads: threads ?? this.threads,
    recap: recap ?? this.recap,
    ending: ending ?? this.ending,
  );
}

class StoryEvent {
  const StoryEvent(this.kind, this.detail);
  final String kind;
  final String detail;
}

class ReducerResult {
  const ReducerResult({
    required this.state,
    required this.events,
    required this.accepted,
  });
  final StoryState state;
  final List<StoryEvent> events;
  final bool accepted;
}

class StoryTemplate {
  const StoryTemplate({
    required this.id,
    required this.title,
    required this.pitch,
    required this.initialSceneId,
    required this.scenes,
    required this.routes,
  });
  final String id;
  final String title;
  final String pitch;
  final String initialSceneId;
  final Map<String, StoryScene> scenes;
  final Map<String, StoryRoute> routes;
  StoryScene scene(String id) => scenes[id]!;
}

class StoryRoute {
  const StoryRoute({
    required this.event,
    this.sceneId,
    this.fact,
    this.thread,
    this.ending,
    this.requiresFact,
    this.blockedDetail,
  });
  final StoryEvent event;
  final String? sceneId;
  final String? fact;
  final StoryThread? thread;
  final String? ending;
  final String? requiresFact;
  final String? blockedDetail;
}
