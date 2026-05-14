#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
  const char *real = "/opt/homebrew/bin/claude";
  const char *ca = "/Users/corptest/Documents/Codex/claude-code-app-api/claude-local-proxy/certs/ca.crt";
  setenv("NODE_USE_SYSTEM_CA", "1", 1);
  setenv("NODE_EXTRA_CA_CERTS", ca, 1);
  setenv("SSL_CERT_FILE", ca, 0);
  setenv("ANTHROPIC_BASE_URL", "https://127.0.0.1:38443/claude-desktop", 1);

  char **next_argv = calloc((size_t)argc + 1, sizeof(char *));
  if (!next_argv) {
    perror("calloc");
    return 127;
  }
  next_argv[0] = (char *)real;
  for (int i = 1; i < argc; i++) next_argv[i] = argv[i];
  next_argv[argc] = NULL;

  execv(real, next_argv);
  perror("execv /opt/homebrew/bin/claude");
  return 127;
}
