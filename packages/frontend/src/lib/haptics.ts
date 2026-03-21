import { useWebHaptics } from 'web-haptics/react';

// Re-export the hook for convenience
export { useWebHaptics };

// Preset types for our app
export type HapticType = 'success' | 'error' | 'nudge' | 'buzz';
