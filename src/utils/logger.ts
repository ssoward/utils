type LogLevel = 'info' | 'warn' | 'error' | 'debug';

function formatTimestamp(): string {
  return new Date().toISOString();
}

function log(level: LogLevel, component: string, message: string, data?: Record<string, unknown>) {
  const entry = {
    timestamp: formatTimestamp(),
    level,
    component,
    message,
    ...(data && { data }),
  };
  const output = JSON.stringify(entry);
  if (level === 'error') {
    console.error(output);
  } else {
    console.log(output);
  }
}

export const logger = {
  info: (component: string, message: string, data?: Record<string, unknown>) =>
    log('info', component, message, data),
  warn: (component: string, message: string, data?: Record<string, unknown>) =>
    log('warn', component, message, data),
  error: (component: string, message: string, data?: Record<string, unknown>) =>
    log('error', component, message, data),
  debug: (component: string, message: string, data?: Record<string, unknown>) =>
    log('debug', component, message, data),
};
