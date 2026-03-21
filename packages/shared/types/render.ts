export interface RenderJobCreateRequest {
  engine: 'cycles' | 'eevee';
  frame_start?: number;
  frame_end?: number;
  samples?: number;
  resolution_x?: number;
  resolution_y?: number;
  output_format?: string;
}

export interface RenderJobResponse {
  id: string;
  status: 'queued' | 'rendering' | 'complete' | 'failed';
  engine: string;
  frame_start: number;
  frame_end: number;
  samples: number | null;
  resolution_x: number;
  resolution_y: number;
  output_format: string;
  frames_done: number;
  render_seconds: number | null;
  cost_nzd: number | null;
  download_url: string | null;
  download_expires: string | null;
  error_message: string | null;
  created_at: string;
  started_at: string | null;
  completed_at: string | null;
}
