'use client';

/**
 * Shared chrome for every signed-in admin page — header (brand +
 * sign-out), left nav, and the auth gate. Mirrors the Partner-tab
 * shell on iOS so both surfaces feel like one product.
 */
import { useEffect } from 'react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { signOut } from 'firebase/auth';
import { LayoutDashboard, MapPin, Plug, ListTree, BookOpen, type LucideIcon } from 'lucide-react';
import { firebaseAuth } from '@/lib/firebase';
import { useAdminAuth } from '@/lib/auth';
import { APP_NAME } from '@/lib/config';
import { cn } from '@/lib/utils';

interface NavItem {
  href: string;
  label: string;
  icon: LucideIcon;
}

const NAV: NavItem[] = [
  { href: '/overview', label: 'Overview', icon: LayoutDashboard },
  { href: '/map', label: 'Map', icon: MapPin },
  { href: '/stations', label: 'Stations', icon: Plug },
  { href: '/sessions', label: 'Sessions', icon: ListTree },
  { href: '/capabilities', label: 'Capabilities', icon: BookOpen },
];

export function DashShell({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const auth = useAdminAuth();

  useEffect(() => {
    if (auth.status === 'signed-out') router.replace('/sign-in');
    if (auth.status === 'not-admin') router.replace('/sign-in?denied=1');
  }, [auth.status, router]);

  if (auth.status !== 'admin') {
    return (
      <main className="flex min-h-screen items-center justify-center text-fg-3">
        <span className="text-sm">Loading…</span>
      </main>
    );
  }

  return (
    <div className="flex min-h-screen flex-col">
      <header className="border-b border-rule bg-surface">
        <div className="mx-auto flex w-full max-w-[1400px] items-center justify-between px-6 py-3">
          <div className="flex items-center gap-2">
            <span className="inline-flex h-7 w-7 items-center justify-center rounded-md bg-accent text-white">
              ⚡
            </span>
            <h1 className="text-sm font-semibold tracking-tight">
              {APP_NAME} <span className="text-fg-3">· Admin</span>
            </h1>
          </div>
          <div className="flex items-center gap-3 text-xs text-fg-3">
            <span>{auth.user.email}</span>
            <button
              type="button"
              onClick={() => signOut(firebaseAuth())}
              className="rounded-md border border-rule px-3 py-1 hover:bg-surface-2"
            >
              Sign out
            </button>
          </div>
        </div>
      </header>

      <div className="mx-auto flex w-full max-w-[1400px] flex-1 gap-6 px-6 py-6">
        <nav className="hidden w-48 shrink-0 md:block">
          <ul className="space-y-1">
            {NAV.map((item) => {
              const active = pathname?.startsWith(item.href);
              const Icon = item.icon;
              return (
                <li key={item.href}>
                  <Link
                    href={item.href}
                    className={cn(
                      'flex items-center gap-2 rounded-md px-3 py-2 text-sm transition',
                      active
                        ? 'bg-accent-tint text-accent'
                        : 'text-fg-2 hover:bg-surface-2',
                    )}
                  >
                    <Icon size={16} />
                    {item.label}
                  </Link>
                </li>
              );
            })}
          </ul>
        </nav>

        <main className="min-w-0 flex-1">{children}</main>
      </div>

      {/* Mobile bottom nav — surfaces the same four targets when the
          sidebar is hidden on small screens. */}
      <nav className="sticky bottom-0 border-t border-rule bg-surface md:hidden">
        <ul className="mx-auto flex max-w-[1400px] items-stretch justify-around">
          {NAV.map((item) => {
            const active = pathname?.startsWith(item.href);
            const Icon = item.icon;
            return (
              <li key={item.href} className="flex-1">
                <Link
                  href={item.href}
                  className={cn(
                    'flex flex-col items-center gap-1 px-2 py-2 text-[10px]',
                    active ? 'text-accent' : 'text-fg-3',
                  )}
                >
                  <Icon size={18} />
                  {item.label}
                </Link>
              </li>
            );
          })}
        </ul>
      </nav>
    </div>
  );
}
