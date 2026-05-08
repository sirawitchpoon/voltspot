import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

/// Standard shadcn/ui helper — merge Tailwind class lists with later
/// classes overriding earlier conflicting utilities.
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
