export interface SyncJobResponseDto {
  jobId: string;
  status: 'accepted' | 'processing' | 'completed' | 'failed';
  receivedAt: string;
  startedAt?: string;
  finishedAt?: string;
  counts: Record<string, number>;
  result?: Record<string, unknown>;
  error?: string;
}