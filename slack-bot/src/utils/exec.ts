import { exec as cpExec } from 'child_process';

export function exec(command: string, timeoutMs = 10_000): Promise<string> {
  return new Promise((resolve, reject) => {
    cpExec(command, { timeout: timeoutMs }, (error, stdout, stderr) => {
      if (error) {
        reject(new Error(`Command failed: ${command}\n${stderr || error.message}`));
        return;
      }
      resolve(stdout.trim());
    });
  });
}
