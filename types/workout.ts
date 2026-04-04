export type ExerciseType = 'pushup' | 'squat';

export type WorkoutSession = {
  id: string;
  startedAt: string;
  endedAt?: string;
  reps: Record<ExerciseType, number>;
};
