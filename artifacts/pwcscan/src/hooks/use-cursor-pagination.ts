import { useCallback, useState } from 'react';

export function useCursorPagination<Cursor extends number | string = number>() {
  const [cursorHistory, setCursorHistory] = useState<Array<Cursor | undefined>>([undefined]);
  const cursor = cursorHistory[cursorHistory.length - 1];
  const hasPrevious = cursorHistory.length > 1;

  const goNext = useCallback((nextCursor?: Cursor | null) => {
    if (nextCursor === null || nextCursor === undefined) return;
    setCursorHistory((history) => {
      if (history[history.length - 1] === nextCursor) return history;
      return [...history, nextCursor];
    });
  }, []);

  const goPrevious = useCallback(() => {
    setCursorHistory((history) => history.length > 1 ? history.slice(0, -1) : history);
  }, []);

  const reset = useCallback(() => setCursorHistory([undefined]), []);

  return { cursor, hasPrevious, goNext, goPrevious, reset };
}
