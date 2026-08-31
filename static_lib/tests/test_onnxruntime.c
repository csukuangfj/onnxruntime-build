// test_onnxruntime.c
//
// A minimal test to verify the onnxruntime static library was built correctly.
// It calls OrtGetApiBase()->GetVersionString() and checks the result.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "onnxruntime_c_api.h"

int main(void) {
  const OrtApiBase *api_base = OrtGetApiBase();
  if (!api_base) {
    fprintf(stderr, "FAILED: OrtGetApiBase() returned NULL\n");
    return 1;
  }

  const char *version = api_base->GetVersionString();
  if (!version || strlen(version) == 0) {
    fprintf(stderr, "FAILED: GetVersionString() returned NULL or empty\n");
    return 1;
  }

  printf("onnxruntime version: %s\n", version);
  printf("PASSED\n");

  return 0;
}
