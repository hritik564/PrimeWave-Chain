export function formatPW(wei: string | null | undefined): string {
  if (wei === null || wei === undefined || wei.trim() === '') return 'Unavailable';
  try {
    const val = BigInt(wei);
    const divisor = BigInt(10 ** 18);
    const integerPart = val / divisor;
    const fractionalPart = val % divisor;
    
    if (fractionalPart === 0n) {
      return `${integerPart.toString()} PW`;
    }
    
    // Convert to string and pad with leading zeros
    const fracStr = fractionalPart.toString().padStart(18, '0');
    // Take first 4 digits and strip trailing zeros
    let formattedFrac = fracStr.substring(0, 4).replace(/0+$/, '');
    
    if (formattedFrac.length === 0) {
      return `${integerPart.toString()} PW`;
    }
    
    return `${integerPart.toString()}.${formattedFrac} PW`;
  } catch (e) {
    return 'Unavailable';
  }
}

export function formatPWCompact(wei: string | null | undefined): string {
  if (wei === null || wei === undefined || wei.trim() === '') return 'Unavailable';
  try {
    const val = BigInt(wei);
    const divisor = BigInt(10 ** 18);
    const pwValue = Number(val / divisor) + Number(val % divisor) / 1e18;
    
    if (pwValue >= 1e9) {
      return `${(pwValue / 1e9).toFixed(2)}B PW`;
    }
    if (pwValue >= 1e6) {
      return `${(pwValue / 1e6).toFixed(2)}M PW`;
    }
    if (pwValue >= 1e3) {
      return `${(pwValue / 1e3).toFixed(2)}K PW`;
    }
    return formatPW(wei);
  } catch (e) {
    return 'Unavailable';
  }
}

export function formatHash(hash: string, chars = 8): string {
  if (!hash) return '';
  if (hash.length <= chars * 2 + 2) return hash;
  return `${hash.substring(0, chars + 2)}...${hash.substring(hash.length - chars)}`;
}

export function formatAddress(addr: string, chars = 6): string {
  return formatHash(addr, chars);
}

export function formatAge(unixTs: number): string {
  if (!Number.isFinite(unixTs)) return 'Unavailable';
  const now = Math.floor(Date.now() / 1000);
  const diff = now - unixTs;
  
  if (diff < 60) return `${diff} secs ago`;
  if (diff < 3600) return `${Math.floor(diff / 60)} mins ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)} hrs ago`;
  return `${Math.floor(diff / 86400)} days ago`;
}

export function formatTimestamp(unixTs: number, utc: boolean): string {
  if (!Number.isFinite(unixTs)) return 'Unavailable';
  const date = new Date(unixTs * 1000);
  
  const options: Intl.DateTimeFormatOptions = {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    timeZoneName: 'short',
    timeZone: utc ? 'UTC' : undefined
  };
  
  return date.toLocaleString('en-US', options);
}

export function formatNumber(n: string | number | null | undefined): string {
  if (n === null || n === undefined) return 'Unavailable';
  const num = typeof n === 'string' ? parseFloat(n) : n;
  if (!Number.isFinite(num)) return 'Unavailable';
  return new Intl.NumberFormat('en-US').format(num);
}

export function formatGas(gas: string | null | undefined): string {
  if (gas === null || gas === undefined || gas.trim() === '') return 'Unavailable';
  return formatNumber(gas);
}

export function formatGasPercent(used: string | null | undefined, limit: string | null | undefined): string {
  if (
    used === null || used === undefined || used.trim() === '' ||
    limit === null || limit === undefined || limit.trim() === ''
  ) return 'Unavailable';
  try {
    const u = BigInt(used);
    const l = BigInt(limit);
    if (l === 0n) return 'Unavailable';
    
    const percent = Number(u * 10000n / l) / 100;
    return `${percent.toFixed(2)}%`;
  } catch (e) {
    return 'Unavailable';
  }
}

export function formatEmissionRate(weiPerSec: string | null | undefined): string {
  if (weiPerSec === null || weiPerSec === undefined || weiPerSec.trim() === '') return 'Unavailable';
  try {
    const weiSec = BigInt(weiPerSec);
    const secondsPerYear = BigInt(365 * 24 * 60 * 60);
    const weiYear = weiSec * secondsPerYear;
    return formatPWCompact(weiYear.toString()) + ' / year';
  } catch (e) {
    return 'Unavailable';
  }
}
