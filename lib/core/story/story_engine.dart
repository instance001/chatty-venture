import 'story_models.dart';

class StoryEngine {
  StoryEngine({StoryTemplate? template})
    : template = template ?? AdventureCatalog.defaultAdventure;
  final StoryTemplate template;
  ReducerResult apply(StoryState state, StoryAction action) {
    if (state.ending != null) {
      return ReducerResult(
        state: state,
        events: const [
          StoryEvent('rejected', 'This tale already has an ending.'),
        ],
        accepted: false,
      );
    }
    final route = template.routes[action.target];
    if (route == null) {
      return _commit(
        state,
        event: StoryEvent('attempted', 'You try: ${action.playerText.trim()}'),
      );
    }
    if (route.requiresFact != null && !state.hasFact(route.requiresFact!)) {
      return ReducerResult(
        state: state,
        events: [
          StoryEvent(
            'blocked',
            route.blockedDetail ?? 'That path is not open yet.',
          ),
        ],
        accepted: false,
      );
    }
    return _commit(
      state,
      sceneId: route.sceneId,
      fact: route.fact,
      thread: route.thread,
      ending: route.ending,
      event: route.event,
    );
  }

  ReducerResult _commit(
    StoryState state, {
    String? sceneId,
    String? fact,
    StoryThread? thread,
    String? ending,
    required StoryEvent event,
  }) {
    final recap = [...state.recap, event.detail];
    if (recap.length > 12) recap.removeRange(0, recap.length - 12);
    final threads = {...state.threads};
    if (thread != null) threads[thread.id] = thread;
    return ReducerResult(
      state: state.copyWith(
        sceneId: sceneId,
        turn: state.turn + 1,
        facts: {...state.facts, ?fact},
        threads: threads,
        recap: recap,
        ending: ending,
      ),
      events: [event],
      accepted: true,
    );
  }
}

class AdventureCatalog {
  static const adventures = [_lantern, _train, _relay];
  static StoryTemplate get defaultAdventure => adventures.first;
  static StoryTemplate byId(String id) =>
      adventures.firstWhere((t) => t.id == id, orElse: () => defaultAdventure);
}

const _lantern = StoryTemplate(
  id: 'lantern_quay',
  title: 'The Bell at Lantern Quay',
  pitch: 'A missing name sleeps beneath a rain-lit harbour.',
  initialSceneId: 'lantern_quay',
  scenes: {
    'lantern_quay': StoryScene(
      id: 'lantern_quay',
      title: 'Lantern Quay',
      description:
          'Rain hushes the sleeping harbour. One blue lantern sways beside the old archive.',
      choices: [
        StoryChoice(id: 'follow_lantern', label: 'Follow the blue lantern'),
        StoryChoice(id: 'speak_keeper', label: 'Speak with the harbour keeper'),
        StoryChoice(id: 'ring_bell', label: 'Ring the silent bell'),
      ],
    ),
    'old_archive': StoryScene(
      id: 'old_archive',
      title: 'The Old Archive',
      description:
          'Salt-stained ledgers climb to the ceiling. A sealed book waits beneath the lantern light.',
      choices: [
        StoryChoice(id: 'read_ledger', label: 'Read the sealed ledger'),
        StoryChoice(id: 'consult_index', label: 'Consult the tide index'),
        StoryChoice(id: 'return_quay', label: 'Return to the quay'),
      ],
    ),
  },
  routes: {
    'follow_lantern': StoryRoute(
      sceneId: 'old_archive',
      fact: 'followed',
      event: StoryEvent(
        'moved',
        'You followed the blue lantern into the old archive.',
      ),
    ),
    'speak_keeper': StoryRoute(
      fact: 'keeper_warned_you',
      thread: StoryThread(
        id: 'the_unpaid_debt',
        label: 'The keeper’s unpaid debt',
        status: 'Find the missing name in the archive.',
      ),
      event: StoryEvent('learned', 'The keeper trusts you with an old debt.'),
    ),
    'read_ledger': StoryRoute(
      requiresFact: 'keeper_warned_you',
      blockedDetail: 'The ledger is sealed by a name you do not know yet.',
      fact: 'missing_name_found',
      thread: StoryThread(
        id: 'the_unpaid_debt',
        label: 'The keeper’s unpaid debt',
        status: 'You found the missing name: Elian Voss.',
      ),
      event: StoryEvent(
        'discovered',
        'You found the missing name: Elian Voss.',
      ),
    ),
    'consult_index': StoryRoute(
      requiresFact: 'keeper_warned_you',
      blockedDetail:
          'The tide index is locked beneath the keeper’s brass seal.',
      fact: 'tide_index_consulted',
      thread: StoryThread(
        id: 'the_unpaid_debt',
        label: 'The keeper’s unpaid debt',
        status: 'A tide mark points toward the ledger’s missing name.',
      ),
      event: StoryEvent(
        'discovered',
        'The tide index marks the ledger with a blue lantern seal.',
      ),
    ),
    'return_quay': StoryRoute(
      sceneId: 'lantern_quay',
      event: StoryEvent('moved', 'You returned to Lantern Quay.'),
    ),
    'ring_bell': StoryRoute(
      requiresFact: 'missing_name_found',
      blockedDetail: 'The bell waits for the hidden name.',
      ending: 'The harbour remembers its lost name.',
      event: StoryEvent('ended', 'The harbour’s lost name has been restored.'),
    ),
  },
);

const _train = StoryTemplate(
  id: 'midnight_train',
  title: 'The Last Train at Meridian',
  pitch: 'A train waits at a platform missing from every timetable.',
  initialSceneId: 'platform_zero',
  scenes: {
    'platform_zero': StoryScene(
      id: 'platform_zero',
      title: 'Platform Zero',
      description: 'Fog gathers around a black train with one lit carriage.',
      choices: [
        StoryChoice(id: 'board', label: 'Board the waiting train'),
        StoryChoice(id: 'porter', label: 'Question the night porter'),
        StoryChoice(id: 'depart', label: 'Name Meridian and board'),
      ],
    ),
    'carriage': StoryScene(
      id: 'carriage',
      title: 'The Lit Carriage',
      description:
          'Velvet seats face an empty table beneath a clicking ticket punch.',
      choices: [
        StoryChoice(id: 'ticket', label: 'Check the ticket'),
        StoryChoice(id: 'listen_punch', label: 'Listen to the ticket punch'),
        StoryChoice(id: 'back', label: 'Return to the platform'),
      ],
    ),
  },
  routes: {
    'board': StoryRoute(
      sceneId: 'carriage',
      event: StoryEvent('moved', 'You board the waiting train.'),
    ),
    'porter': StoryRoute(
      fact: 'warning',
      thread: StoryThread(
        id: 'missing_stop',
        label: 'The missing stop',
        status: 'Learn the name the train is waiting for.',
      ),
      event: StoryEvent(
        'learned',
        'The porter says the train stops only for a forgotten name.',
      ),
    ),
    'ticket': StoryRoute(
      requiresFact: 'warning',
      blockedDetail: 'The ticket’s ink will not settle yet.',
      fact: 'meridian',
      thread: StoryThread(
        id: 'missing_stop',
        label: 'The missing stop',
        status: 'Meridian is the name the train is waiting for.',
      ),
      event: StoryEvent(
        'discovered',
        'The ticket names Meridian as the lost stop.',
      ),
    ),
    'listen_punch': StoryRoute(
      fact: 'punch_pattern',
      thread: StoryThread(
        id: 'missing_stop',
        label: 'The missing stop',
        status: 'The punch clicks three times, then waits for a name.',
      ),
      event: StoryEvent(
        'learned',
        'The ticket punch clicks a patient pattern: three beats and a pause.',
      ),
    ),
    'back': StoryRoute(
      sceneId: 'platform_zero',
      event: StoryEvent('moved', 'You return to Platform Zero.'),
    ),
    'depart': StoryRoute(
      requiresFact: 'meridian',
      blockedDetail: 'The train waits for its lost destination.',
      ending:
          'The train takes your spoken destination and slips quietly into the fog.',
      thread: StoryThread(
        id: 'missing_stop',
        label: 'The missing stop',
        status: 'Resolved.',
      ),
      event: StoryEvent('ended', 'The last train departs for Meridian.'),
    ),
  },
);

const _relay = StoryTemplate(
  id: 'ashfall_relay',
  title: 'Ashfall Relay',
  pitch: 'A dying beacon repeats a message beyond a red storm.',
  initialSceneId: 'relay_room',
  scenes: {
    'relay_room': StoryScene(
      id: 'relay_room',
      title: 'Relay Room',
      description:
          'Ash brushes the glass. A beacon pulses with an unfinished transmission.',
      choices: [
        StoryChoice(id: 'tune', label: 'Tune the beacon'),
        StoryChoice(id: 'decode', label: 'Decode the transmission'),
        StoryChoice(id: 'suit', label: 'Inspect the exterior suit'),
        StoryChoice(id: 'airlock', label: 'Open the airlock'),
        StoryChoice(id: 'send', label: 'Answer the beacon'),
      ],
    ),
    'walk': StoryScene(
      id: 'walk',
      title: 'Service Walk',
      description:
          'A narrow rail crosses the outpost hull beneath slow red ash.',
      choices: [
        StoryChoice(id: 'trace', label: 'Trace the signal'),
        StoryChoice(id: 'return', label: 'Return to the relay room'),
      ],
    ),
  },
  routes: {
    'tune': StoryRoute(
      fact: 'signal',
      thread: StoryThread(
        id: 'lost_signal',
        label: 'The unfinished transmission',
        status: 'Find where the message begins.',
      ),
      event: StoryEvent(
        'learned',
        'The beacon resolves into a repeating three-note signal.',
      ),
    ),
    'decode': StoryRoute(
      requiresFact: 'signal',
      blockedDetail:
          'The beacon needs a clear frequency before its message can be read.',
      fact: 'reply_phrase',
      thread: StoryThread(
        id: 'lost_signal',
        label: 'The unfinished transmission',
        status: 'The message begins: “Relay holds. Answer by light.”',
      ),
      event: StoryEvent(
        'discovered',
        'The transmission begins with a request to answer by light.',
      ),
    ),
    'suit': StoryRoute(
      fact: 'suit',
      event: StoryEvent(
        'discovered',
        'The exterior suit still holds a careful charge.',
      ),
    ),
    'airlock': StoryRoute(
      requiresFact: 'suit',
      blockedDetail: 'The storm is too fierce without a charged suit.',
      sceneId: 'walk',
      event: StoryEvent('moved', 'You step onto the service walk.'),
    ),
    'trace': StoryRoute(
      requiresFact: 'signal',
      blockedDetail: 'The signal needs a frequency first.',
      fact: 'source',
      thread: StoryThread(
        id: 'lost_signal',
        label: 'The unfinished transmission',
        status: 'The source is beneath the northern ridge.',
      ),
      event: StoryEvent(
        'discovered',
        'The beacon points beneath the northern ridge.',
      ),
    ),
    'return': StoryRoute(
      sceneId: 'relay_room',
      event: StoryEvent('moved', 'You return to the relay room.'),
    ),
    'send': StoryRoute(
      requiresFact: 'source',
      blockedDetail: 'You need the signal’s source before you can answer.',
      ending:
          'You answer the beacon. Beneath the red storm, a distant light answers once.',
      thread: StoryThread(
        id: 'lost_signal',
        label: 'The unfinished transmission',
        status: 'Resolved.',
      ),
      event: StoryEvent('ended', 'The relay’s message is answered.'),
    ),
  },
);
