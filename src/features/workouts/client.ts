/**
 * Server documents of «Тренировки» and the writes to them.
 * Every PUT/DELETE carries the version (`updatedAt`) this client last saw. On a 409 (or a missing
 * document) the whole snapshot is reloaded and a `WorkoutConflictNotice` is thrown: a write is never
 * repeated with a newer version behind the owner's back.
 */
import type { WorkoutDoc, WorkoutKind, WorkoutsSnapshot } from '../../../shared/types';
import {
  bestDocId,
  isDefaultSettings,
  readBest,
  readProgram,
  readRecord,
  readSettings,
  writeBest,
  writeProgram,
  writeRecord,
  writeSettings,
} from './codec';
import {
  SETTINGS_DOC_ID,
  isValidDocId,
  type Best,
  type Exercise,
  type MuscleKey,
  type Program,
  type WorkoutRecord,
  type WorkoutSettings,
} from './model';
import { sortRecords } from './stats';

export interface WorkoutsTransport {
  load(): Promise<WorkoutsSnapshot>;
  put(
    kind: WorkoutKind,
    id: string,
    data: Record<string, unknown>,
    expected: string | null,
  ): Promise<WorkoutDoc>;
  remove(kind: WorkoutKind, id: string, expected: string): Promise<void>;
}
export class WorkoutConflictNotice extends Error {
  constructor() {
    super('workout-conflict');
    this.name = 'WorkoutConflictNotice';
  }
}
export const isConflictStatus = (status: number | undefined) => status === 409 || status === 404;

export interface WorkoutsState {
  programs: Program[];
  custom: Exercise[];
  records: WorkoutRecord[];
  bests: Best[];
  settings: WorkoutSettings;
}
export const EMPTY_STATE: WorkoutsState = {
  programs: [],
  custom: [],
  records: [],
  bests: [],
  settings: { linkedHabitID: null, lastTickedDay: null },
};
type Docs = Record<WorkoutKind, Map<string, WorkoutDoc>>;
const emptyDocs = (): Docs => ({
  programs: new Map(),
  sessions: new Map(),
  records: new Map(),
  settings: new Map(),
});
const toDocs = (snapshot: WorkoutsSnapshot): Docs => {
  const docs = emptyDocs();
  for (const kind of Object.keys(docs) as WorkoutKind[])
    for (const doc of snapshot[kind] ?? []) docs[kind].set(doc.id, doc);
  return docs;
};

/** Programs ordered by `order` (ties by id); custom exercises from the program docs, newest doc wins. */
export function deriveState(docs: Docs): WorkoutsState {
  const programs = [...docs.programs.values()].flatMap((doc) => {
    const read = readProgram(doc.id, doc.data);
    return read ? [{ ...read, updatedAt: doc.updatedAt }] : [];
  });
  const ordered = [...programs].sort(
    (a, b) =>
      (a.order ?? Number.MAX_VALUE) - (b.order ?? Number.MAX_VALUE) ||
      (a.program.id < b.program.id ? -1 : 1),
  );
  const custom = new Map<string, Exercise>();
  [...programs]
    .sort((a, b) => Date.parse(a.updatedAt) - Date.parse(b.updatedAt))
    .forEach((doc) => doc.exercises.forEach((exercise) => custom.set(exercise.id, exercise)));
  const records = [...docs.sessions.values()].flatMap((doc) => readRecord(doc.id, doc.data) ?? []);
  const bests = [...docs.records.values()].flatMap((doc) => readBest(doc.data) ?? []);
  const settings = docs.settings.get(SETTINGS_DOC_ID);
  return {
    programs: ordered.map((doc) => doc.program),
    custom: [...custom.values()],
    records: sortRecords(records),
    bests,
    settings: settings ? readSettings(settings.data) : EMPTY_STATE.settings,
  };
}

const stable = (value: unknown): unknown =>
  Array.isArray(value)
    ? value.map(stable)
    : value && typeof value === 'object'
      ? Object.fromEntries(
          Object.entries(value)
            .sort(([a], [b]) => (a < b ? -1 : 1))
            .map(([key, item]) => [key, stable(item)]),
        )
      : value;
/** Equality of two documents regardless of key order. */
export const sameJson = (a: unknown, b: unknown) =>
  JSON.stringify(stable(a)) === JSON.stringify(stable(b));

export class WorkoutsClient {
  state: WorkoutsState = EMPTY_STATE;
  loaded = false;
  private docs: Docs = emptyDocs();
  private listeners = new Set<() => void>();
  private tail: Promise<unknown> = Promise.resolve();
  /** Own exercises that are not in any saved program yet. */
  private pendingCustom = new Map<string, Exercise>();

  constructor(private transport: WorkoutsTransport) {}

  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };
  private publish() {
    const derived = deriveState(this.docs);
    const known = new Set(derived.custom.map((exercise) => exercise.id));
    known.forEach((id) => this.pendingCustom.delete(id));
    const extra = [...this.pendingCustom.values()];
    this.state = { ...derived, custom: [...derived.custom, ...extra] };
    this.listeners.forEach((listener) => listener());
  }

  /** Reads the whole snapshot; queued behind pending writes so a read never lands in the middle of one. */
  load(): Promise<void> {
    return this.enqueue(() => this.reload());
  }
  private async reload(): Promise<void> {
    this.docs = toDocs(await this.transport.load());
    this.loaded = true;
    this.publish();
  }
  /** Remembers an own exercise until a program that uses it is saved. */
  rememberExercise(exercise: Exercise) {
    this.pendingCustom.set(exercise.id, exercise);
    this.publish();
  }

  private enqueue<T>(job: () => Promise<T>): Promise<T> {
    const run = this.tail.then(job, job);
    this.tail = run.catch(() => undefined);
    return run;
  }
  private async guard<T>(write: () => Promise<T>): Promise<T> {
    try {
      return await write();
    } catch (error) {
      const status = (error as { status?: number }).status;
      if (isConflictStatus(status)) {
        await this.reload().catch(() => undefined);
        throw new WorkoutConflictNotice();
      }
      throw error;
    }
  }
  private async put(kind: WorkoutKind, id: string, data: Record<string, unknown>) {
    if (!isValidDocId(id)) throw new Error(`Invalid workout document id: ${id}`);
    const current = this.docs[kind].get(id);
    const saved = await this.transport.put(kind, id, data, current?.updatedAt ?? null);
    this.docs[kind].set(id, { id, updatedAt: saved.updatedAt, data: saved.data ?? data });
  }
  private async remove(kind: WorkoutKind, id: string) {
    const current = this.docs[kind].get(id);
    if (!current) return;
    try {
      await this.transport.remove(kind, id, current.updatedAt);
    } catch (error) {
      if ((error as { status?: number }).status !== 404) throw error;
    }
    this.docs[kind].delete(id);
  }
  /** Runs a write; resolves to true once it was stored (never to undefined, which `write` uses for failure). */
  private run(job: () => Promise<unknown>): Promise<true> {
    return this.enqueue(() =>
      this.guard(async () => {
        await job();
        this.publish();
        return true as const;
      }),
    );
  }

  private rawOf(kind: WorkoutKind, id: string) {
    return this.docs[kind].get(id)?.data ?? {};
  }
  /** Writes the programs that differ from the stored ones (and their order) and removes vanished ones. */
  saveProgramList(programs: readonly Program[], custom: readonly Exercise[] = this.state.custom) {
    return this.run(async () => {
      const keep = new Set(programs.map((program) => program.id));
      for (const id of [...this.docs.programs.keys()])
        if (!keep.has(id)) await this.remove('programs', id);
      await this.rewritePrograms(programs, custom);
    });
  }
  /** One finished workout, the records it set, and optionally an updated program, in this order. */
  saveFinished(finished: WorkoutRecord, changedBests: readonly Best[], program?: Program) {
    return this.run(async () => {
      // An earlier attempt of this same workout may have been stored already: its version is in `docs`.
      await this.put(
        'sessions',
        finished.id,
        writeRecord(finished, this.rawOf('sessions', finished.id)),
      );
      for (const best of changedBests) {
        const id = bestDocId(best);
        await this.put('records', id, writeBest(best, this.rawOf('records', id)));
      }
      if (program) {
        const programs = this.state.programs.map((item) =>
          item.id === program.id ? program : item,
        );
        await this.rewritePrograms(programs);
      }
    });
  }
  private async rewritePrograms(
    programs: readonly Program[],
    custom: readonly Exercise[] = this.state.custom,
  ) {
    for (const [order, program] of programs.entries()) {
      const used = custom.filter((exercise) =>
        program.items.some((item) => item.exerciseID === exercise.id),
      );
      const data = writeProgram(program, order, used, this.rawOf('programs', program.id));
      if (!sameJson(data, this.docs.programs.get(program.id)?.data))
        await this.put('programs', program.id, data);
    }
  }
  saveBest(best: Best) {
    return this.run(() =>
      this.put('records', bestDocId(best), writeBest(best, this.rawOf('records', bestDocId(best)))),
    );
  }
  /** Sets or clears the group of an own exercise; the programs that use it carry the new group. */
  setMuscle(exerciseID: string, muscle: MuscleKey | null) {
    return this.run(async () => {
      const pending = this.pendingCustom.get(exerciseID);
      if (pending) this.pendingCustom.set(exerciseID, { ...pending, muscle });
      const custom = this.state.custom.map((exercise) =>
        exercise.id === exerciseID ? { ...exercise, muscle } : exercise,
      );
      const users = this.state.programs.filter((program) =>
        program.items.some((item) => item.exerciseID === exerciseID),
      );
      if (users.length) await this.rewritePrograms(this.state.programs, custom);
    });
  }
  /** Settings: the doc is absent while everything is at its default. */
  saveSettings(settings: WorkoutSettings) {
    return this.run(async () => {
      if (isDefaultSettings(settings)) return this.remove('settings', SETTINGS_DOC_ID);
      await this.put(
        'settings',
        SETTINGS_DOC_ID,
        writeSettings(settings, this.rawOf('settings', SETTINGS_DOC_ID)),
      );
    });
  }
}
