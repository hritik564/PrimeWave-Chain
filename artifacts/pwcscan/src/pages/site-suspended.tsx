import { ServerCrash } from 'lucide-react';

export default function SiteSuspended() {
  return (
    <main
      className="min-h-screen bg-background px-6 py-16 text-foreground"
      aria-labelledby="site-suspended-title"
    >
      <div className="mx-auto flex min-h-[calc(100vh-8rem)] max-w-2xl items-center justify-center">
        <section className="w-full rounded-2xl border border-border bg-card p-8 text-center shadow-sm sm:p-12">
          <div
            className="mx-auto mb-6 flex h-16 w-16 items-center justify-center rounded-full bg-destructive/10 text-destructive"
            aria-hidden="true"
          >
            <ServerCrash className="h-8 w-8" />
          </div>
          <p className="mb-3 text-sm font-semibold uppercase tracking-[0.2em] text-muted-foreground">
            PWCScan
          </p>
          <h1
            id="site-suspended-title"
            className="font-display text-3xl font-bold tracking-tight sm:text-4xl"
          >
            Server suspended
          </h1>
          <p className="mx-auto mt-4 max-w-lg text-base leading-7 text-muted-foreground sm:text-lg">
            The PrimeWave Explorer is temporarily unavailable while the server is
            suspended. Please try again later.
          </p>
          <p
            className="mt-8 text-sm font-medium text-muted-foreground"
            role="status"
          >
            Explorer access is currently unavailable.
          </p>
        </section>
      </div>
    </main>
  );
}