import type { UserResponse } from './auth';

export interface AdminUserResponse extends UserResponse {
  balance_nzd: number;
}

export interface UserUpdateRequest {
  status?: string;
  role?: string;
  hard_limit_nzd?: number;
  services_enabled?: string[];
}

export interface AdjustBalanceRequest {
  amount_nzd: number;
  description: string;
}

export interface SystemStatsResponse {
  total_users: number;
  active_users: number;
  total_inference_cost_nzd: number;
  total_render_cost_nzd: number;
  jobs_in_queue: number;
}
