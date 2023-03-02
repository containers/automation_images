#
# Lang. ref: https://github.com/bazelbuild/starlark/blob/master/spec.md#contents
# Impl. ref: https://cirrus-ci.org/guide/programming-tasks/
load("cirrus", "fs")

def main():
  return {
    "env": {
      "IMG_SFX": fs.read("IMG_SFX").strip(),
      "IMPORT_IMG_SFX": fs.read("IMPORT_IMG_SFX").strip()
    },
  }
