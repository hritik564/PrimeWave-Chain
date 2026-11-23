import { createContext, useContext, useEffect, useState, ReactNode } from 'react';

type Theme = 'light' | 'dark' | 'system';
type AddressDisplay = 'truncated' | 'full';
type TimeFormat = 'local' | 'utc';

interface SettingsState {
  theme: Theme;
  addressDisplay: AddressDisplay;
  timeFormat: TimeFormat;
  autoRefresh: boolean;
  setTheme: (theme: Theme) => void;
  setAddressDisplay: (display: AddressDisplay) => void;
  setTimeFormat: (format: TimeFormat) => void;
  setAutoRefresh: (autoRefresh: boolean) => void;
}

const SettingsContext = createContext<SettingsState | undefined>(undefined);

export function SettingsProvider({ children }: { children: ReactNode }) {
  const [theme, setThemeState] = useState<Theme>(
    (localStorage.getItem('pwc-theme') as Theme) || 'light'
  );
  const [addressDisplay, setAddressDisplayState] = useState<AddressDisplay>(
    (localStorage.getItem('pwc-addr-display') as AddressDisplay) || 'truncated'
  );
  const [timeFormat, setTimeFormatState] = useState<TimeFormat>(
    (localStorage.getItem('pwc-time-format') as TimeFormat) || 'local'
  );
  const [autoRefresh, setAutoRefreshState] = useState<boolean>(
    localStorage.getItem('pwc-auto-refresh') !== 'false'
  );

  useEffect(() => {
    const root = window.document.documentElement;
    root.classList.remove('light', 'dark');

    if (theme === 'system') {
      const systemTheme = window.matchMedia('(prefers-color-scheme: dark)').matches
        ? 'dark'
        : 'light';
      root.classList.add(systemTheme);
    } else {
      root.classList.add(theme);
    }
  }, [theme]);

  const setTheme = (newTheme: Theme) => {
    localStorage.setItem('pwc-theme', newTheme);
    setThemeState(newTheme);
  };

  const setAddressDisplay = (display: AddressDisplay) => {
    localStorage.setItem('pwc-addr-display', display);
    setAddressDisplayState(display);
  };

  const setTimeFormat = (format: TimeFormat) => {
    localStorage.setItem('pwc-time-format', format);
    setTimeFormatState(format);
  };

  const setAutoRefresh = (refresh: boolean) => {
    localStorage.setItem('pwc-auto-refresh', refresh.toString());
    setAutoRefreshState(refresh);
  };

  return (
    <SettingsContext.Provider
      value={{
        theme,
        addressDisplay,
        timeFormat,
        autoRefresh,
        setTheme,
        setAddressDisplay,
        setTimeFormat,
        setAutoRefresh,
      }}
    >
      {children}
    </SettingsContext.Provider>
  );
}

export function useSettings() {
  const context = useContext(SettingsContext);
  if (context === undefined) {
    throw new Error('useSettings must be used within a SettingsProvider');
  }
  return context;
}
