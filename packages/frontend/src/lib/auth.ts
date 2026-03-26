const TOKEN_KEY = "gpushare_token";

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}

export function setToken(token: string): void {
  localStorage.setItem(TOKEN_KEY, token);
}

export function clearToken(): void {
  localStorage.removeItem(TOKEN_KEY);
}

export function isAuthenticated(): boolean {
  const token = getToken();
  if (!token) return false;
  const payload = parseToken();
  if (!payload) return false;
  return payload.exp * 1000 > Date.now();
}

interface TokenPayload {
  sub: string;
  role: string;
  exp: number;
}

export function parseToken(): {
  sub: string;
  role: string;
  exp: number;
} | null {
  const token = getToken();
  if (!token) return null;
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const payload = JSON.parse(atob(parts[1]));
    return payload;
  } catch {
    return null;
  }
}

export function isGuest(): boolean {
  const payload = parseToken();
  return payload?.role === "guest" || payload?.sub === "guest";
}
